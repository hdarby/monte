import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/amateur_policy.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

import '../_helpers.dart';

/// A recreational player at a given skill, with the default 0.5 position
/// awareness that separates them from a pro's 0.9.
PlayerProfile _rec({double skill = 0.45}) => PlayerProfile(
      id: 'A1',
      name: 'Rec',
      archetype: 'Home_Game_Amateur',
      skill: skill,
      strategicBaseline: const StrategicBaseline(
        vpipTarget: 0.34,
        pfrTarget: 0.16,
        threeBetFrequency: 0.03,
        gtoAdherenceWeight: 0.4,
      ),
      behavioralModifiers: const BehavioralModifiers(
        tiltResistance: 0.5,
        exploitativeWeight: 0.25,
        riskPremiumCoefficient: 1.0,
        weightOnOpponentHistory: 0.3,
      ),
    );

/// A 9-handed game with [hero] holding [cards] in the given seat.
PokerGame _game({
  required int heroSeat,
  required List<Card> hole,
  int button = 0,
}) {
  final placed = <int, Card>{heroSeat: hole[0], heroSeat + 9: hole[1]};
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
  )
    ..buttonIndex = button
    ..startHand();
}

Player _seat(PokerGame g, int i) => g.players[i];

void main() {
  const trials = 200;

  group('the small blind completing into a multiway limped pot', () {
    /// Folds everyone to a set of limpers, then leaves the small blind to act.
    PokerGame limpedTo({required int limpers}) {
      final g = _game(heroSeat: 1, hole: [card('7c'), card('2d')]);
      // Seats act from under the gun (button 0 → SB is seat 1).
      var limped = 0;
      while (g.currentPlayer != null && g.currentPlayer!.id != 'p1') {
        if (limped < limpers) {
          g.applyAction(const GameAction.call());
          limped++;
        } else {
          g.applyAction(const GameAction.fold());
        }
      }
      return g;
    }

    double completeRate(PokerGame Function() spot, {double skill = 0.45}) {
      var calls = 0;
      for (var i = 0; i < trials; i++) {
        final g = spot();
        final a = AmateurPolicy(_rec(skill: skill), random: Random(100 + i))
            .decide(g, _seat(g, 1));
        if (a.type == ActionType.call) calls++;
      }
      return calls / trials;
    }

    test('a rec completes with anything once the pot is multiway', () {
      // 7-2 offsuit. The price feels like enough on its own; that it plays every
      // street out of position against several opponents does not register.
      expect(completeRate(() => limpedTo(limpers: 3)), greaterThan(0.5),
          reason: 'the classic small-blind chip leak');
    });

    test('but not when only one player limped', () {
      expect(completeRate(() => limpedTo(limpers: 1)), lessThan(0.35),
          reason: 'the pot-odds illusion needs a multiway pot to appear');
    });

    test('a skilled player does not make the mistake', () {
      expect(completeRate(() => limpedTo(limpers: 3), skill: 1.0),
          lessThan(0.35),
          reason: 'the leak scales with incompetence and vanishes at skill 1');
    });
  });

  group('the button is defended backwards', () {
    /// One raise, then [callers] cold-callers, leaving the button to act.
    PokerGame raisedTo({required int callers, required List<Card> hole}) {
      final g = _game(heroSeat: 0, hole: hole);
      var raised = false, called = 0;
      while (g.currentPlayer != null && g.currentPlayer!.id != 'p0') {
        if (!raised) {
          g.applyAction(GameAction.raise(g.minRaiseTo(g.currentPlayer!)));
          raised = true;
        } else if (called < callers) {
          g.applyAction(const GameAction.call());
          called++;
        } else {
          g.applyAction(const GameAction.fold());
        }
      }
      return g;
    }

    /// Continues across a spread of marginal holdings, so the comparison does
    /// not hinge on finding one hand sitting exactly on the threshold.
    double continueRate(int callers) {
      const marginal = ['Tc 7d', '9c 6d', 'Jc 5d', '8c 5c', 'Qc 4d', 'Kc 6d'];
      var on = 0, n = 0;
      for (final h in marginal) {
        for (var i = 0; i < 40; i++) {
          final g = raisedTo(callers: callers, hole: cards(h));
          final a = AmateurPolicy(_rec(), random: Random(200 + i))
              .decide(g, _seat(g, 0));
          if (a.type != ActionType.fold) on++;
          n++;
        }
      }
      return on / n;
    }

    test('over-defends multiway, under-defends heads-up', () {
      // Backwards on both counts: heads-up in position is where the button is
      // worth defending, and a multiway pot is where a weak holding is
      // dominated by several people at once.
      expect(continueRate(2), greaterThan(continueRate(0)),
          reason: 'a rec continues more the more people are already in');
    });
  });
}
