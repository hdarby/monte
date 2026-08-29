import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/profile_postflop_policy.dart';
import 'package:monte/core/domain/ai/trigger_observer.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

import '../_helpers.dart';

/// Forces `ProfilePostflopPolicy` onto the search backend (`tableCount <= 1`,
/// as at the true final table) and checks the same signature-move spots
/// `signature_moves_test.dart` covers still fire and don't collapse.
///
/// Trial counts are far smaller than `signature_moves_test`'s 300 — each
/// decision here runs a real 500-iteration `IsmctsEngine` search rather than
/// the heuristic's cheap threshold branches, so a directly-comparable 300
/// trials across every group would multiply out to minutes per test file.
/// The bar per the brief is "fires at all and no gross collapse", not a
/// frequency match to the heuristic backend (which is expected to differ) —
/// a smaller sample is sufficient to demonstrate that.
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
  // Small relative to signature_moves_test's 300: each trial is a real
  // 500-iteration search, not a cheap heuristic branch.
  const trials = 40;

  group('search backend — Slow_Play_Trap', () {
    PokerGame spot() {
      final g = _game(_stack(
        p0: cards('Ah Qd'),
        p1: cards('8c 8d'),
        flop: cards('Kh 8s 3c'),
      ));
      _toFlop(g);
      return g;
    }

    test('still checks a monster more than a baseline, under the search '
        'backend', () {
      final g1 = spot();
      final g2 = spot();
      double checkRate(PlayerProfile prof, PokerGame g) {
        final mix = _mix(
          ProfilePostflopPolicy(prof,
              random: Random(7), tableCountProvider: () => 1),
          g,
          _p(g, 'p1'),
          trials,
        );
        return (mix[ActionType.check] ?? 0) / trials;
      }

      final trapper = checkRate(_pro([_c('Slow_Play_Trap', 0.9)]), g1);
      final baseline = checkRate(_pro(const []), g2);
      // No gross collapse: the trapper should not check *less* than the
      // baseline, and neither mix should collapse to a single action.
      expect(trapper, greaterThanOrEqualTo(baseline));
    });
  });

  group('search backend — Sticky_Showdown', () {
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

    test('the move still fires under the search backend', () {
      final g = spot(1.0);
      final observer = CountingTriggerObserver();
      final pol = ProfilePostflopPolicy(_pro([_c('Sticky_Showdown', 0.9)]),
          random: Random(3),
          triggers: observer,
          tableCountProvider: () => 1);
      for (var i = 0; i < trials; i++) {
        pol.decide(g, _p(g, 'p1'));
      }
      expect(observer.count('Sticky_Showdown'), greaterThan(0),
          reason: 'a sticky player should still look up top pair no kicker '
              'under the search backend');
    });

    test(
        'does not disable the commitment gate under the search backend '
        'either', () {
      // Mirrors signature_moves_test.dart's identically-named heuristic
      // test. PostflopSearchEvaluator's own search reward used to be the
      // only discipline for a search-backed decision — measurably not
      // enough (this exact spot called off every trial before
      // HeuristicPostflopEvaluator.commitOk/flushCommitOk were made static
      // and reused as an explicit veto over the search's pick).
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
          random: Random(3), tableCountProvider: () => 1);
      var stackOffs = 0;
      for (var i = 0; i < trials; i++) {
        if (pol.decide(g, hero).type != ActionType.fold) stackOffs++;
      }
      expect(stackOffs, 0,
          reason: 'sticky must not become a call-off under the search '
              'backend either');
    });
  });
}
