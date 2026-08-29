import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/ismcts.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

import '../_helpers.dart';

/// Same deal-stacking helper as `ismcts_test.dart`.
List<Card> _stack({
  required List<Card> p0,
  required List<Card> p1,
  required List<Card> board,
}) {
  final placed = <int, Card>{
    0: p0[0],
    2: p0[1],
    1: p1[0],
    3: p1[1],
    5: board[0],
    6: board[1],
    7: board[2],
    9: board[3],
    11: board[4],
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

PokerGame _headsUp(List<Card> dealOrder) => PokerGame(
  players: [
    Player(id: 'p0', name: 'P0', stack: 1000, isHuman: true),
    Player(id: 'p1', name: 'P1', stack: 1000),
  ],
  deck: Deck.stacked(dealOrder),
)..startHand();

void _passiveUntilRiver(PokerGame g) {
  while (g.round != BettingRound.river) {
    final p = g.currentPlayer!;
    g.applyAction(
      g.canCheck(p) ? const GameAction.check() : const GameAction.call(),
    );
  }
}

void main() {
  group('IsmctsEngine.evaluateEdges', () {
    test('the visit-weighted winner matches chooseAction — same search, '
        'two views', () {
      final order = _stack(
        p0: cards('2c 7d'),
        p1: cards('Ah Kh'),
        board: cards('Qh Jh Th 2s 3d'),
      );
      final game = _headsUp(order);
      _passiveUntilRiver(game);
      final hero = game.currentPlayer!;

      final chosen = IsmctsEngine(
        config: const IsmctsConfig(iterations: 500),
        random: Random(7),
      ).chooseAction(game, hero);

      final edges = IsmctsEngine(
        config: const IsmctsConfig(iterations: 500),
        random: Random(7),
      ).evaluateEdges(game, hero);

      expect(edges, isNotEmpty);
      var winner = edges.first;
      for (final e in edges) {
        if (e.visits > winner.visits ||
            (e.visits == winner.visits && e.meanReward > winner.meanReward)) {
          winner = e;
        }
      }

      expect(winner.action.type, chosen.type);
      expect(winner.action.amount, chosen.amount);
    });

    test('folding a hopeless hand: fold has the most visits among the edges',
        () {
      final order = _stack(
        p0: cards('3c 4d'),
        p1: cards('5h 6s'),
        board: cards('As Ks Qd 7h 2c'),
      );
      final game = _headsUp(order);
      _passiveUntilRiver(game);
      game.applyAction(const GameAction.bet(990));
      final hero = game.currentPlayer!;

      final edges = IsmctsEngine(
        config: const IsmctsConfig(iterations: 500),
        random: Random(2),
      ).evaluateEdges(game, hero);

      var winner = edges.first;
      for (final e in edges) {
        if (e.visits > winner.visits ||
            (e.visits == winner.visits && e.meanReward > winner.meanReward)) {
          winner = e;
        }
      }
      expect(winner.action.type, ActionType.fold);
    });
  });
}
