import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/ismcts.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

import '../_helpers.dart';

/// Builds a 52-card deal order for a heads-up hand that places the given hole
/// cards and 5-card [board] at the positions the engine deals them, then fills
/// the rest. Deal sequence: p0,p1,p0,p1 holes; burn; flop×3; burn; turn; burn;
/// river.
List<Card> _stack({
  required List<Card> p0,
  required List<Card> p1,
  required List<Card> board, // [f1, f2, f3, turn, river]
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
  group('IsmctsEngine', () {
    test('a preset deck deals the same known board every hand', () {
      // Sanity: Deck.stacked survives startHand's reset+shuffle.
      final order = _stack(
        p0: cards('Ah Kh'),
        p1: cards('2c 7d'),
        board: cards('Qh Jh Th 2s 3d'),
      );
      final g = _headsUp(order);
      expect(g.players[0].hole, cards('Ah Kh'));
      _passiveUntilRiver(g);
      expect(g.board, cards('Qh Jh Th 2s 3d'));
    });

    test('value-bets the nuts on the river', () {
      // Hero p1 acts first on the river holding a royal flush.
      final order = _stack(
        p0: cards('2c 7d'),
        p1: cards('Ah Kh'),
        board: cards('Qh Jh Th 2s 3d'),
      );
      final game = _headsUp(order);
      _passiveUntilRiver(game);
      final hero = game.currentPlayer!;
      expect(hero.id, 'p1');

      final action = IsmctsEngine(
        config: const IsmctsConfig(iterations: 1000),
        random: Random(1),
      ).chooseAction(game, hero);

      expect(action.type, ActionType.bet, reason: 'the nuts should bet/raise');
    });

    test('folds a hopeless hand facing an all-in', () {
      // Hero p0 acts last; villain shoves the river. Hero has nothing.
      final order = _stack(
        p0: cards('3c 4d'),
        p1: cards('5h 6s'),
        board: cards('As Ks Qd 7h 2c'),
      );
      final game = _headsUp(order);
      _passiveUntilRiver(game);
      game.applyAction(const GameAction.bet(990)); // villain (p1) all-in
      final hero = game.currentPlayer!;
      expect(hero.id, 'p0');

      final action = IsmctsEngine(
        config: const IsmctsConfig(iterations: 1000),
        random: Random(2),
      ).chooseAction(game, hero);

      expect(action.type, ActionType.fold);
    });

    test('is reproducible under a fixed seed', () {
      final order = _stack(
        p0: cards('2c 7d'),
        p1: cards('Ah Kh'),
        board: cards('Qh Jh Th 2s 3d'),
      );
      final game = _headsUp(order);
      _passiveUntilRiver(game);
      final hero = game.currentPlayer!;

      GameAction choose() => IsmctsEngine(
        config: const IsmctsConfig(iterations: 300),
        random: Random(7),
      ).chooseAction(game, hero);

      final a = choose();
      final b = choose();
      expect(a.type, b.type);
      expect(a.amount, b.amount);
    });
  });
}
