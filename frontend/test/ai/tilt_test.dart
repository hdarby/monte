import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/amateur_policy.dart';
import 'package:monte/core/domain/ai/characteristic_catalog.dart';
import 'package:monte/core/domain/ai/mental_state.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/profile_calibrator.dart';
import 'package:monte/core/domain/ai/profile_policy.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

import '../_helpers.dart';

PlayerProfile _profile({
  required double tiltResistance,
  List<PlayerCharacteristic> chars = const [],
  double skill = 1.0,
}) =>
    PlayerProfile(
      id: 'T1',
      name: 'Subject',
      archetype: 'Test',
      skill: skill,
      strategicBaseline: const StrategicBaseline(
        vpipTarget: 0.26,
        pfrTarget: 0.20,
        threeBetFrequency: 0.08,
        gtoAdherenceWeight: 0.9,
      ),
      behavioralModifiers: BehavioralModifiers(
        tiltResistance: tiltResistance,
        exploitativeWeight: 0.3,
        riskPremiumCoefficient: 1.0,
        weightOnOpponentHistory: 0.5,
      ),
      generalTraits: const GeneralTraits(
        positionAwareness: 0.9,
        potOdds: 0.9,
        impliedOdds: 0.85,
      ),
      characteristics: chars,
    );

PlayerCharacteristic _c(String id, double p) =>
    PlayerCharacteristic(id: id, proficiency: p);

/// A fixed mental state for one seat, so a policy can be tested at a chosen
/// level of tilt without playing hands to get there.
class _FixedMood implements MentalReads {
  _FixedMood(this.state);
  final MentalState state;
  @override
  MentalState? stateFor(String seatId) => state;
}

/// Applies [hands] losing pots of [lossBb] each and returns the final state.
MentalState _afterLosses({
  required PlayerProfile profile,
  required int hands,
  required double lossBb,
}) {
  const model = MentalModel();
  var s = const MentalState();
  for (var i = 0; i < hands; i++) {
    s = model.afterResult(
      state: s,
      profile: profile,
      net: (-lossBb * 100).round(),
      bigBlind: 100,
      enteredPot: true,
    );
  }
  return s;
}

void main() {
  group('the catalog', () {
    test('the three tilt styles are registered', () {
      final known = characteristicCatalog.map((c) => c.id).toSet();
      for (final id in const ['Tilt_Blowup', 'Tilt_Chase', 'Tilt_Shutdown']) {
        expect(known, contains(id));
      }
    });
  });

  group('how pressure builds', () {
    test('a big loss rattles a player; a small one does not', () {
      final rec = _profile(tiltResistance: 0.4);
      expect(_afterLosses(profile: rec, hands: 1, lossBb: 3).tiltPressure, 0);
      expect(_afterLosses(profile: rec, hands: 1, lossBb: 60).tiltPressure,
          greaterThan(0));
    });

    test('tilt_resistance is what decides who tilts', () {
      // The field that has been authored on all 184 profiles and read by
      // nothing until now.
      final rec = _afterLosses(
          profile: _profile(tiltResistance: 0.35), hands: 3, lossBb: 60);
      final pro = _afterLosses(
          profile: _profile(tiltResistance: 0.99), hands: 3, lossBb: 60);
      expect(rec.isTilted, isTrue, reason: 'a rec steams');
      expect(pro.isTilted, isFalse, reason: 'an ice-cold pro does not');
      expect(rec.tiltPressure, greaterThan(pro.tiltPressure * 5));
    });

    test('it fades when the beats stop', () {
      const model = MentalModel();
      final profile = _profile(tiltResistance: 0.4);
      var s = _afterLosses(profile: profile, hands: 3, lossBb: 60);
      expect(s.isTilted, isTrue);
      for (var i = 0; i < 12; i++) {
        s = model.afterResult(
            state: s, profile: profile, net: 0, bigBlind: 100, enteredPot: false);
      }
      expect(s.isTilted, isFalse, reason: 'nobody stays on tilt forever');
    });

    test('it is bounded, however bad the run', () {
      final s = _afterLosses(
          profile: _profile(tiltResistance: 0.1), hands: 60, lossBb: 400);
      expect(s.tiltPressure, lessThanOrEqualTo(1.0));
    });

    test('boredom counts folds and resets the moment they play', () {
      const model = MentalModel();
      final profile = _profile(tiltResistance: 0.9);
      var s = const MentalState();
      for (var i = 0; i < 20; i++) {
        s = model.afterResult(
            state: s, profile: profile, net: -100, bigBlind: 100,
            enteredPot: false);
      }
      expect(s.handsSinceVpip, 20);
      expect(MentalModel.boredom(s), greaterThan(0));

      s = model.afterResult(
          state: s, profile: profile, net: 0, bigBlind: 100, enteredPot: true);
      expect(s.handsSinceVpip, 0);
      expect(MentalModel.boredom(s), 0);
    });
  });

  group('the three styles look different', () {
    /// Every one of the 169 canonical starting hands, so the measurement is a
    /// real opening frequency rather than a verdict on a handful of holdings —
    /// a small sample leaves gaps exactly where the widening boundary lands.
    final allHands = <List<Card>>[
      for (var hi = 2; hi <= 14; hi++)
        for (var lo = 2; lo <= hi; lo++)
          for (final suited in (hi == lo ? [false] : [false, true]))
            [
              Card(Rank.values.firstWhere((r) => r.value == hi), Suit.spades),
              Card(
                Rank.values.firstWhere((r) => r.value == lo),
                suited ? Suit.spades : Suit.hearts,
              ),
            ],
    ];

    /// Deals [hole] to the button, folds everyone to it, and returns the action.
    /// [opened] puts a raise in front of the hero first — the only preflop spot
    /// where continuing *passively* is available at all, since first-in on the
    /// button it is raise or fold.
    ActionType act(
      PlayerProfile profile,
      MentalReads? mood,
      List<Card> hole, {
      bool opened = false,
      int seed = 5,
    }) {
      final placed = <int, Card>{0: hole[0], 9: hole[1]};
      final used = placed.values.toSet();
      final rest = [
        for (final s in Suit.values)
          for (final r in Rank.values)
            if (!used.contains(Card(r, s))) Card(r, s),
      ];
      var k = 0;
      final order = [for (var x = 0; x < 52; x++) placed[x] ?? rest[k++]];
      final g = PokerGame(
        players: [
          for (var x = 0; x < 9; x++)
            Player(id: 'p$x', name: 'P$x', stack: 20000),
        ],
        smallBlind: 100,
        bigBlind: 200,
        deck: Deck.stacked(order),
        rotateButton: false,
      )..startHand();
      var raised = !opened;
      while (g.currentPlayer != null && g.currentPlayer!.id != 'p0') {
        final cur = g.currentPlayer!;
        if (!raised) {
          g.applyAction(GameAction.raise(g.minRaiseTo(cur)));
          raised = true;
        } else {
          g.applyAction(const GameAction.fold());
        }
      }
      final hero = g.currentPlayer;
      if (hero == null) return ActionType.fold;
      return ProfilePolicy(
        profile,
        ranges: const ProfileCalibrator().rangesFor(profile),
        random: Random(seed),
        mental: mood,
      ).decide(g, hero).type;
    }

    ({double enter, double raise}) measure(
      PlayerProfile profile,
      MentalReads? mood, {
      bool opened = false,
    }) {
      var entered = 0, raises = 0;
      for (final h in allHands) {
        final a = act(profile, mood, h, opened: opened);
        if (a != ActionType.fold) entered++;
        if (a == ActionType.raise) raises++;
      }
      return (
        enter: entered / allHands.length,
        raise: raises / allHands.length,
      );
    }

    final tilted = _FixedMood(const MentalState(tiltPressure: 0.8));

    test('the baseline has room to move in both directions', () {
      final calm = measure(_profile(tiltResistance: 0.3), null);
      expect(calm.enter, greaterThan(0.1));
      expect(calm.enter, lessThan(0.9));
    });

    test('a blow-up plays more hands, and arrives raising', () {
      final p = _profile(tiltResistance: 0.3, chars: [_c('Tilt_Blowup', 0.9)]);
      expect(measure(p, tilted).enter, greaterThan(measure(p, null).enter));
      expect(measure(p, tilted).raise, greaterThan(measure(p, null).raise));
    });

    test('a chaser comes along rather than taking over', () {
      // Facing an open, where continuing passively is possible at all.
      final p = _profile(tiltResistance: 0.3, chars: [_c('Tilt_Chase', 0.9)]);
      final calm = measure(p, null, opened: true);
      final mad = measure(p, tilted, opened: true);
      expect(mad.enter, greaterThan(calm.enter), reason: 'more hands');
      expect(mad.enter - mad.raise, greaterThan(calm.enter - calm.raise),
          reason: 'and the extra ones are calls, not raises');
    });

    test('a shutdown plays fewer hands — tilt is not always aggression', () {
      final p = _profile(tiltResistance: 0.3, chars: [_c('Tilt_Shutdown', 0.9)]);
      expect(measure(p, tilted).enter, lessThan(measure(p, null).enter));
    });

    test('a blow-up and a chaser are told apart by *how* they widen', () {
      final blowup =
          _profile(tiltResistance: 0.3, chars: [_c('Tilt_Blowup', 0.9)]);
      final chaser =
          _profile(tiltResistance: 0.3, chars: [_c('Tilt_Chase', 0.9)]);
      expect(measure(blowup, tilted).raise,
          greaterThan(measure(chaser, tilted).raise));
    });

    test('a profile with no tilt style plays exactly as before', () {
      // 154 pros were never given one; none of them may change behaviour.
      final p = _profile(tiltResistance: 0.3);
      expect(measure(p, tilted).enter, measure(p, null).enter);
      expect(measure(p, tilted).raise, measure(p, null).raise);
    });
  });

  group('postflop', () {
    test('a chasing rec calls down wider than the same rec calm', () {
      final rec = _profile(
        tiltResistance: 0.3,
        skill: 0.5,
        chars: [_c('Tilt_Chase', 0.9)],
      );
      double foldRate(MentalReads? mood) {
        var folds = 0;
        const n = 120;
        for (var i = 0; i < n; i++) {
          final placed = <int, Card>{
            0: card('7h'), 2: card('6s'), 1: card('Kc'), 3: card('2d'),
            5: card('Kh'), 6: card('Qs'), 7: card('Jd'),
            9: card('9c'), 11: card('5h'),
          };
          final used = placed.values.toSet();
          final rest = [
            for (final s in Suit.values)
              for (final r in Rank.values)
                if (!used.contains(Card(r, s))) Card(r, s),
          ];
          var k = 0;
          final order = [for (var x = 0; x < 52; x++) placed[x] ?? rest[k++]];
          final g = PokerGame(
            players: [
              Player(id: 'p0', name: 'P0', stack: 1000, isHuman: true),
              Player(id: 'p1', name: 'P1', stack: 1000),
            ],
            deck: Deck.stacked(order),
          )..startHand();
          while (g.round == BettingRound.preflop) {
            final p = g.currentPlayer!;
            g.applyAction(g.canCheck(p)
                ? const GameAction.check()
                : const GameAction.call());
          }
          while (g.round != BettingRound.river) {
            g.applyAction(const GameAction.check());
            g.applyAction(const GameAction.check());
          }
          g.applyAction(const GameAction.check());
          final villain = g.currentPlayer!;
          g.applyAction(
              GameAction.bet(villain.currentBet + (g.pot * 1.0).round()));
          final hero = g.players.firstWhere((x) => x.id == 'p1');
          final a = AmateurPolicy(rec, random: Random(9 + i), mental: mood)
              .decide(g, hero);
          if (a.type == ActionType.fold) folds++;
        }
        return folds / n;
      }

      expect(foldRate(_FixedMood(const MentalState(tiltPressure: 0.8))),
          lessThan(foldRate(null)),
          reason: 'they call to prove a point');
    });
  });
}
