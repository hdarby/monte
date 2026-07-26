import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/icm_adjusted_decider.dart';
import 'package:monte/core/domain/ai/push_fold_chart.dart';
import 'package:monte/core/domain/ai/tournament_context.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

import '../../_helpers.dart';

// Hero is the button in a 3-handed hand (first to act preflop), holding [hero]
// with a [stackBb]-big-blind stack; returns the game with hero on the button.
(PokerGame, Player) _short(List<Card> hero, {int stackBb = 5}) {
  const bb = 20;
  final players = [
    Player(id: 'h', name: 'H', stack: stackBb * bb),
    Player(id: 'a', name: 'A', stack: 1000),
    Player(id: 'b', name: 'B', stack: 1000),
  ];
  final g = PokerGame(
    players: players,
    smallBlind: bb ~/ 2,
    bigBlind: bb,
    deck: Deck(random: Random(1)),
  )..startHand();
  final h = g.currentPlayer!; // the button/hero acts first 3-handed
  h.hole
    ..clear()
    ..addAll(hero);
  return (g, h);
}

TournamentContext _ctx({double stackBb = 5, double bubble = 1.0}) =>
    TournamentContext(
      stackInBb: stackBb,
      bubbleFactor: bubble,
      playersLeft: 4,
      paidPlaces: 3,
      inMoney: false,
    );

class _Fixed implements DecisionPolicy {
  const _Fixed(this.action);
  final GameAction action;
  @override
  GameAction decide(PokerGame g, Player p) => action;
}

void main() {
  group('PushFoldChart', () {
    const chart = PushFoldChart();

    test('a short stack jams a premium and folds trash', () {
      final (gAces, aces) = _short(cards('As Ac'));
      expect(chart.decide(gAces, aces, _ctx()).type, ActionType.raise);

      final (gTrash, trash) = _short(cards('7c 2d'));
      expect(chart.decide(gTrash, trash, _ctx()).type, ActionType.fold);
    });

    test('the jam range tightens as the bubble factor rises', () {
      final hands = [
        'Ah 9c', 'Kd Ts', 'Qc Jd', 'Ts 9s', 'Ad 5c', 'Kh 8d',
        'Jc Td', 'Qh 9h', 'As 4d', 'Kc 9s', 'Jh Ts', 'Qd 8d',
      ].map(cards).toList();
      int jams(double bubble) {
        var n = 0;
        for (final h in hands) {
          final (g, hero) = _short(h);
          if (chart.decide(g, hero, _ctx(bubble: bubble)).type == ActionType.raise) {
            n++;
          }
        }
        return n;
      }

      expect(jams(2.0), lessThan(jams(1.0)),
          reason: 'ICM pressure narrows the shove range');
    });
  });

  group('IcmAdjustedDecider', () {
    test('near the bubble it folds a big call that it makes off the bubble', () {
      GameAction wrapped(double bubble, List<Card> hand) {
        final players = [
          Player(id: 'p0', name: 'P0', stack: 1000),
          Player(id: 'p1', name: 'P1', stack: 1000),
        ];
        final g = PokerGame(
          players: players,
          smallBlind: 10,
          bigBlind: 20,
          deck: Deck(random: Random(2)),
        )
          ..buttonIndex = 1
          ..startHand();
        g.applyAction(GameAction.raise(g.maxRaiseTo(g.currentPlayer!)));
        final hero = g.currentPlayer!; // p0 (BB), ~50bb, facing an all-in
        hero.hole
          ..clear()
          ..addAll(hand);
        final decider = IcmAdjustedDecider(
          const _Fixed(GameAction.call()),
          (game, p) => _ctx(stackBb: 50, bubble: bubble),
        );
        return decider.decide(g, hero);
      }

      const marginal = 'Kd Ts'; // not a premium — a coin-flip-ish bluff-catch
      expect(wrapped(1.0, cards(marginal)).type, ActionType.call,
          reason: 'off the bubble the inner call passes through');
      expect(wrapped(1.8, cards(marginal)).type, ActionType.fold,
          reason: 'on the bubble the big call is demoted to a fold');
    });

    test('a short stack is put on push/fold regardless of the inner brain', () {
      // Inner would call, but at 5bb preflop the chart takes over and folds trash.
      final (g, hero) = _short(cards('7c 2d'));
      final decider = IcmAdjustedDecider(
        const _Fixed(GameAction.call()),
        (game, p) => _ctx(stackBb: 5),
      );
      expect(decider.decide(g, hero).type, ActionType.fold);
    });
  });
}
