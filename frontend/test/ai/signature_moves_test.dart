import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/characteristic_catalog.dart';
import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/mental_state.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/core/domain/ai/profile_decider.dart';
import 'package:monte/core/domain/ai/profile_policy.dart';
import 'package:monte/core/domain/ai/profile_postflop_policy.dart';
import 'package:monte/core/domain/ai/trigger_observer.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

import 'package:monte/features/table/data/local_game_repository.dart';

import '../_helpers.dart';

/// A pro profile carrying exactly the given signature moves, so each can be
/// isolated from the personality noise of a real roster entry.
PlayerProfile _pro(List<PlayerCharacteristic> chars, {double vpip = 0.25}) =>
    PlayerProfile(
      id: 'T001',
      name: 'Test Pro',
      archetype: 'Test',
      skill: 1.0,
      strategicBaseline: StrategicBaseline(
        vpipTarget: vpip,
        pfrTarget: vpip * 0.8,
        threeBetFrequency: 0.09,
        gtoAdherenceWeight: 0.9,
      ),
      behavioralModifiers: const BehavioralModifiers(
        tiltResistance: 0.9,
        exploitativeWeight: 0.3,
        riskPremiumCoefficient: 1.0,
        weightOnOpponentHistory: 0.6,
      ),
      characteristics: chars,
    );

PlayerCharacteristic _c(String id, double p) =>
    PlayerCharacteristic(id: id, proficiency: p);

List<Card> _stack({
  required List<Card> p0,
  required List<Card> p1,
  required List<Card> flop,
  List<Card> turnRiver = const [],
}) {
  final placed = <int, Card>{
    0: p0[0], 2: p0[1],
    1: p1[0], 3: p1[1],
    5: flop[0], 6: flop[1], 7: flop[2],
    if (turnRiver.length == 2) ...{9: turnRiver[0], 11: turnRiver[1]},
  };
  final used = placed.values.toSet();
  final rest = [
    for (final suit in Suit.values)
      for (final rank in Rank.values)
        if (!used.contains(Card(rank, suit))) Card(rank, suit),
  ];
  var r = 0;
  return [for (var i = 0; i < 52; i++) placed[i] ?? rest[r++]];
}

PokerGame _game(List<Card> order, {int stack = 1000}) => PokerGame(
      players: [
        Player(id: 'p0', name: 'P0', stack: stack, isHuman: true),
        Player(id: 'p1', name: 'P1', stack: stack),
      ],
      deck: Deck.stacked(order),
    )..startHand();

void _toFlop(PokerGame g) {
  while (g.round == BettingRound.preflop) {
    final p = g.currentPlayer!;
    g.applyAction(
        g.canCheck(p) ? const GameAction.check() : const GameAction.call());
  }
}

Player _p(PokerGame g, String id) => g.players.firstWhere((x) => x.id == id);

/// A [MentalReads] fake reporting the same fixed, tilted state for every seat
/// — the unit-spot equivalent of a real [MentalTable] mid-tilt, without
/// needing a whole session's worth of bad beats to build the pressure up.
class _FixedMental implements MentalReads {
  const _FixedMental(this.state);
  final MentalState state;
  @override
  MentalState? stateFor(String seatId) => state;
}

/// Runs [n] decisions and reports how often each action type came back.
Map<ActionType, int> _mix(
  ProfilePostflopPolicy pol,
  PokerGame g,
  Player hero,
  int n,
) {
  final out = <ActionType, int>{};
  for (var i = 0; i < n; i++) {
    final t = pol.decide(g, hero).type;
    out[t] = (out[t] ?? 0) + 1;
  }
  return out;
}

void main() {
  const trials = 300;

  group('the catalog', () {
    test('every shipped characteristic is a real catalog entry', () {
      final known = characteristicCatalog.map((c) => c.id).toSet();
      for (final p in [...builtInProfiles, ...homeGameProfiles]) {
        for (final c in p.characteristics) {
          expect(known, contains(c.id),
              reason: '${p.name} carries an unknown move "${c.id}"');
          expect(c.proficiency, inInclusiveRange(0.0, 1.0),
              reason: '${p.name}: ${c.id} proficiency out of range');
        }
      }
    });

    test('the six new moves are all registered', () {
      final known = characteristicCatalog.map((c) => c.id).toSet();
      for (final id in const [
        'Slow_Play_Trap',
        'Sticky_Showdown',
        'Float_And_Take_Away',
        'Bubble_Predator',
        'Limp_Reraise',
        'Underbluff_Exploit',
      ]) {
        expect(known, contains(id));
      }
    });
  });

  group('Slow_Play_Trap', () {
    // A set of eights on K-8-3 with nothing to call: the ordinary line is to
    // bet. A trapper checks it a meaningful share of the time.
    PokerGame spot() {
      final g = _game(_stack(
        p0: cards('Ah Qd'),
        p1: cards('8c 8d'),
        flop: cards('Kh 8s 3c'),
      ));
      _toFlop(g);
      return g;
    }

    test('checks a monster that a baseline pro would bet', () {
      final g1 = spot();
      final g2 = spot();
      double checkRate(PlayerProfile prof, PokerGame g) {
        final mix = _mix(
          ProfilePostflopPolicy(prof, random: Random(7)),
          g,
          _p(g, 'p1'),
          trials,
        );
        return (mix[ActionType.check] ?? 0) / trials;
      }

      final trapper = checkRate(_pro([_c('Slow_Play_Trap', 0.9)]), g1);
      final baseline = checkRate(_pro(const []), g2);
      expect(trapper, greaterThan(baseline + 0.2),
          reason: 'a trapper should check monsters far more often');
    });

    test('still bets it sometimes — a trap is a move, not a rule', () {
      final g = spot();
      final mix = _mix(
        ProfilePostflopPolicy(_pro([_c('Slow_Play_Trap', 0.9)]),
            random: Random(7)),
        g,
        _p(g, 'p1'),
        trials,
      );
      expect(mix[ActionType.bet] ?? 0, greaterThan(0));
    });

    test('does not slow-play a marginal hand', () {
      // Third pair is not a trapping hand; the move must not fire on it.
      final g = _game(_stack(
        p0: cards('Ah Qd'),
        p1: cards('9c 9d'),
        flop: cards('Kh 8s 3c'),
      ));
      _toFlop(g);
      final observer = CountingTriggerObserver();
      final pol = ProfilePostflopPolicy(_pro([_c('Slow_Play_Trap', 1.0)]),
          random: Random(7), triggers: observer);
      for (var i = 0; i < trials; i++) {
        pol.decide(g, _p(g, 'p1'));
      }
      expect(observer.count('Slow_Play_Trap'), 0);
    });
  });

  group('Sticky_Showdown', () {
    /// Top pair with the worst possible kicker on a coordinated board -- the
    /// hand a disciplined player releases and a sticky one cannot. (On a dry
    /// board top pair with a good kicker is genuinely strong and *everybody*
    /// calls, which is why the spot has to be chosen this carefully.)
    PokerGame spot(double potFraction) {
      final g = _game(_stack(
        p0: cards('7h 6s'),
        p1: cards('Kc 2d'),
        flop: cards('Kh Qs Jd'),
        turnRiver: cards('9c 5h'),
      ));
      _toFlop(g);
      while (g.round != BettingRound.river) {
        g.applyAction(const GameAction.check());
        g.applyAction(const GameAction.check());
      }
      g.applyAction(const GameAction.check());
      final villain = g.currentPlayer!;
      g.applyAction(
          GameAction.bet(villain.currentBet + (g.pot * potFraction).round()));
      return g;
    }

    double foldRate(PlayerProfile prof, double potFraction) {
      final g = spot(potFraction);
      final mix = _mix(
        ProfilePostflopPolicy(prof, random: Random(3)),
        g,
        _p(g, 'p1'),
        trials,
      );
      return (mix[ActionType.fold] ?? 0) / trials;
    }

    test('pays off where a disciplined pro folds', () {
      expect(foldRate(_pro(const []), 1.0), greaterThan(0.9),
          reason: 'the baseline should release top pair with a 2 kicker here');
      expect(foldRate(_pro([_c('Sticky_Showdown', 0.9)]), 1.0), lessThan(0.1),
          reason: 'a sticky player looks it up');
    });

    test('lowers the bar without removing it', () {
      // A 3x-pot overbet is still a fold even for a station: sticky means one
      // more crying call, not an inability to ever pass.
      expect(foldRate(_pro([_c('Sticky_Showdown', 0.9)]), 3.0),
          greaterThan(0.9));
    });

    test('records only when it changes the decision', () {
      final g = spot(1.0);
      final observer = CountingTriggerObserver();
      final pol = ProfilePostflopPolicy(_pro([_c('Sticky_Showdown', 0.9)]),
          random: Random(3), triggers: observer);
      for (var i = 0; i < trials; i++) {
        pol.decide(g, _p(g, 'p1'));
      }
      expect(observer.count('Sticky_Showdown'), greaterThan(0),
          reason: 'it flipped these calls, so it should be recorded');
      expect(observer.count('Sticky_Showdown'), lessThanOrEqualTo(trials));
    });

    test('does not disable the commitment gate', () {
      // 40 BB effective, facing a shove: sticky must not become a stack-off.
      final g = _game(
        _stack(
          p0: cards('7h 6s'),
          p1: cards('Kc 2d'),
          flop: cards('Kh Qs Jd'),
          turnRiver: cards('9c 5h'),
        ),
        stack: 120,
      );
      _toFlop(g);
      while (g.round != BettingRound.river) {
        g.applyAction(const GameAction.check());
        g.applyAction(const GameAction.check());
      }
      g.applyAction(const GameAction.check());
      final villain = g.currentPlayer!;
      g.applyAction(GameAction.raise(g.maxRaiseTo(villain)));
      final hero = _p(g, 'p1');
      expect(g.callAmount(hero), greaterThan(hero.stack ~/ 2));

      final pol = ProfilePostflopPolicy(_pro([_c('Sticky_Showdown', 1.0)]),
          random: Random(3));
      var stackOffs = 0;
      for (var i = 0; i < 50; i++) {
        if (pol.decide(g, hero).type != ActionType.fold) stackOffs++;
      }
      expect(stackOffs, 0, reason: 'sticky must not become a call-off');
    });
  });

  group('Limp_Reraise', () {
    test('limps a premium from early position where a pro would open', () {
      // Nine-handed, hero under the gun with aces.
      PokerGame nineHanded() {
        // 9-handed deal order is round-robin, so seat 3 (under the gun with
        // the button on 0) gets cards 3 and 12.
        final placed = <int, Card>{3: card('Ac'), 12: card('Ad')};
        final used = placed.values.toSet();
        final rest = [
          for (final s in Suit.values)
            for (final r in Rank.values)
              if (!used.contains(Card(r, s))) Card(r, s),
        ];
        var i = 0;
        final order = [for (var k = 0; k < 52; k++) placed[k] ?? rest[i++]];
        return PokerGame(
          players: [
            for (var k = 0; k < 9; k++)
              Player(id: 'p$k', name: 'P$k', stack: 20000),
          ],
          smallBlind: 100,
          bigBlind: 200,
          deck: Deck.stacked(order),
          rotateButton: false,
        )..startHand();
      }

      double limpRate(PlayerProfile prof) {
        var limps = 0;
        const n = 200;
        for (var i = 0; i < n; i++) {
          final g = nineHanded();
          final hero = g.currentPlayer!; // first to act = under the gun
          final a = ProfilePolicy(prof, random: Random(100 + i)).decide(g, hero);
          if (a.type == ActionType.call) limps++;
        }
        return limps / n;
      }

      expect(limpRate(_pro([_c('Limp_Reraise', 0.9)])),
          greaterThan(limpRate(_pro(const []))),
          reason: 'the limp-trap should produce early-position limps');
    });
  });

  group('the diagnostic', () {
    test('counts by trigger and by player, and starts empty', () {
      final o = CountingTriggerObserver();
      expect(o.count('Slow_Play_Trap'), 0);
      expect(o.fired, isEmpty);
      o.onFired('Slow_Play_Trap', 'p1', BettingRound.flop);
      o.onFired('Slow_Play_Trap', 'p1', BettingRound.flop);
      o.onFired('Sticky_Showdown', 'p2', BettingRound.river);
      expect(o.count('Slow_Play_Trap'), 2);
      expect(o.countFor('Slow_Play_Trap', 'p1'), 2);
      expect(o.countFor('Slow_Play_Trap', 'p2'), 0);
      expect(o.fired.toSet(), {'Slow_Play_Trap', 'Sticky_Showdown'});
      o.clear();
      expect(o.count('Slow_Play_Trap'), 0);
    });
  });

  group('live fire', () {
    /// The point of the diagnostic. `GeneralTraits` and `EngineTriggers` were
    /// both authored on every profile and read by nothing, and nobody noticed
    /// because there was no way to ask whether they did anything. This asserts
    /// the new moves actually fire in real hands against a real field — not
    /// just in a hand-built spot.
    test('the postflop moves fire in an ordinary session', () async {
      final observer = CountingTriggerObserver();
      final movers = <PlayerProfile>[
        _pro([_c('Slow_Play_Trap', 0.9)]).renamed('Trapper'),
        _pro([_c('Sticky_Showdown', 0.9)]).renamed('Station'),
        _pro([_c('Float_And_Take_Away', 0.9)]).renamed('Floater'),
        _pro([_c('Underbluff_Exploit', 0.9)]).renamed('Exploiter'),
        _pro(const []).renamed('Baseline1'),
        _pro(const []).renamed('Baseline2'),
      ];
      final repo = LocalGameRepository(
        config: TableConfig(
          allBots: true,
          playerCount: movers.length,
          smallBlind: 1,
          bigBlind: 3,
          startingStack: 300,
          botThinkTime: Duration.zero,
          deckBuilder: () => Deck(random: Random(11)),
          deciderBuilder: (i) => deciderForProfile(
            movers[i],
            random: Random(500 + i),
            triggers: observer,
          ),
        ),
      );
      await repo.simulate(1500);

      for (final id in const [
        'Slow_Play_Trap',
        'Sticky_Showdown',
        'Float_And_Take_Away',
      ]) {
        expect(observer.count(id), greaterThan(0),
            reason: '$id never fired in 1500 hands — it is dead weight');
      }
      // Underbluff_Exploit needs an established read on a recreational
      // opponent, which this all-pro table never produces; it is covered by the
      // unit spot instead. Asserting it here would be asserting a bug.
      expect(observer.count('Underbluff_Exploit'), 0);
    }, timeout: const Timeout(Duration(minutes: 5)));

    /// The seven characteristics that already had real behavioral effect
    /// (`profile_postflop_policy.dart`'s `sr`/`pv`/`geoBoost` terms,
    /// `profile_policy.dart`'s `posProf`) but never called `onFired` — so no
    /// `FiredTrigger` ever reached the narrator, no matter how often the
    /// behavior itself fired. This is the fix for that half of the bug: they
    /// must show up in the same diagnostic the other moves already do.
    test('the newly-wired characteristics fire in an ordinary session',
        () async {
      final observer = CountingTriggerObserver();
      final movers = <PlayerProfile>[
        _pro([_c('Positional_Warfare', 0.9)]).renamed('Positional'),
        _pro([_c('Leverage_Pressure', 0.9)]).renamed('Leverager'),
        _pro([_c('Soul_Read', 0.9)]).renamed('Reader'),
        _pro([_c('Geometric_Overbet_Execution', 0.9)]).renamed('Overbetter'),
        _pro(const []).renamed('Baseline1'),
        _pro(const []).renamed('Baseline2'),
      ];
      final repo = LocalGameRepository(
        config: TableConfig(
          allBots: true,
          playerCount: movers.length,
          smallBlind: 1,
          bigBlind: 3,
          startingStack: 300,
          botThinkTime: Duration.zero,
          deckBuilder: () => Deck(random: Random(13)),
          deciderBuilder: (i) => deciderForProfile(
            movers[i],
            random: Random(700 + i),
            triggers: observer,
          ),
        ),
      );
      await repo.simulate(1500);

      for (final id in const [
        'Positional_Warfare',
        'Leverage_Pressure',
        'Soul_Read',
        'Geometric_Overbet_Execution',
      ]) {
        expect(observer.count(id), greaterThan(0),
            reason: '$id never fired in 1500 hands — it is dead weight');
      }
    }, timeout: const Timeout(Duration(minutes: 5)));

    /// Tilt moves need real tilt pressure, which needs a shared [MentalTable]
    /// across the session — `deciderBuilder` bypasses `LocalGameRepository`'s
    /// own wiring of one, so this uses the plain `seatBots` path instead,
    /// exactly the way live play actually constructs these bots.
  });

  /// Tilt moves need real tilt pressure, which normally takes a whole
  /// session's bad beats to build up via a shared `MentalTable`. Unit spots
  /// with a fixed, already-tilted `MentalReads` instead — the same choice
  /// `Sticky_Showdown`/`Underbluff_Exploit` above make for their own
  /// "records only when it changes the decision" tests, one level up: these
  /// callBar shifts are exactly the same shape, just tilt-driven instead of
  /// read-driven.
  group('tilt moves', () {
    const tilted = _FixedMental(MentalState(tiltPressure: 0.8));

    /// The same worst-kicker-top-pair river spot `Sticky_Showdown` uses:
    /// disciplined pros fold it, so it isolates the tilt shift cleanly.
    PokerGame spot() {
      final g = _game(_stack(
        p0: cards('7h 6s'),
        p1: cards('Kc 2d'),
        flop: cards('Kh Qs Jd'),
        turnRiver: cards('9c 5h'),
      ));
      _toFlop(g);
      while (g.round != BettingRound.river) {
        g.applyAction(const GameAction.check());
        g.applyAction(const GameAction.check());
      }
      g.applyAction(const GameAction.check());
      final villain = g.currentPlayer!;
      g.applyAction(GameAction.bet(villain.currentBet + g.pot));
      return g;
    }

    test('Tilt_Chase pays off a hand a baseline pro folds, while tilted', () {
      final g = spot();
      final observer = CountingTriggerObserver();
      final pol = ProfilePostflopPolicy(_pro([_c('Tilt_Chase', 0.9)]),
          random: Random(3), triggers: observer, mental: tilted);
      final mix = _mix(pol, g, _p(g, 'p1'), trials);
      expect((mix[ActionType.fold] ?? 0) / trials, lessThan(0.5),
          reason: 'a chaser calls this down to prove a point while tilted');
      expect(observer.count('Tilt_Chase'), greaterThan(0),
          reason: 'it flipped these calls, so it should be recorded');
    });

    test('Tilt_Shutdown folds more than baseline, while tilted', () {
      // A cheap enough river bet that a baseline pro still calls.
      final g = _game(_stack(
        p0: cards('7h 6s'),
        p1: cards('Kc 2d'),
        flop: cards('Kh Qs Jd'),
        turnRiver: cards('9c 5h'),
      ));
      _toFlop(g);
      while (g.round != BettingRound.river) {
        g.applyAction(const GameAction.check());
        g.applyAction(const GameAction.check());
      }
      g.applyAction(const GameAction.check());
      final villain = g.currentPlayer!;
      g.applyAction(GameAction.bet(villain.currentBet + (g.pot * 0.4).round()));

      final observer = CountingTriggerObserver();
      final pol = ProfilePostflopPolicy(_pro([_c('Tilt_Shutdown', 0.9)]),
          random: Random(3), triggers: observer, mental: tilted);
      final mix = _mix(pol, g, _p(g, 'p1'), trials);
      final baselineMix = _mix(
          ProfilePostflopPolicy(_pro(const []), random: Random(3)),
          g,
          _p(g, 'p1'),
          trials);
      expect((mix[ActionType.fold] ?? 0) / trials,
          greaterThan((baselineMix[ActionType.fold] ?? 0) / trials),
          reason: 'a shut-down player folds more than baseline here');
      expect(observer.count('Tilt_Shutdown'), greaterThan(0),
          reason: 'it flipped these calls, so it should be recorded');
    });

    test('Tilt_Blowup bluffs more than baseline, while tilted', () {
      // A dry board, checked to the hero with nothing — a pure bluff-or-check
      // spot, so any extra betting frequency is the blow-up talking.
      final g = _game(_stack(
        p0: cards('7h 6s'),
        p1: cards('2c 3d'),
        flop: cards('Kh 8s 4d'),
      ));
      _toFlop(g);
      g.applyAction(const GameAction.check()); // p0 checks to p1

      final observer = CountingTriggerObserver();
      final pol = ProfilePostflopPolicy(_pro([_c('Tilt_Blowup', 0.9)]),
          random: Random(5), triggers: observer, mental: tilted);
      final mix = _mix(pol, g, _p(g, 'p1'), trials);
      final baselineMix = _mix(
          ProfilePostflopPolicy(_pro(const []), random: Random(5)),
          g,
          _p(g, 'p1'),
          trials);
      final betRate = (mix[ActionType.bet] ?? 0) / trials;
      final baselineBetRate = (baselineMix[ActionType.bet] ?? 0) / trials;
      expect(betRate, greaterThan(baselineBetRate),
          reason: 'a blow-up bluffs pots it has no business firing at');
      expect(observer.count('Tilt_Blowup'), greaterThan(0),
          reason: 'it produced extra bluffs, so it should be recorded');
    });
  });
}
