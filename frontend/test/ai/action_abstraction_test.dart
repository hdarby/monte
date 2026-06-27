import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/action_abstraction.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

PokerGame _headsUp({int p0 = 1000, int p1 = 1000, int seed = 7}) => PokerGame(
  players: [
    Player(id: 'p0', name: 'P0', stack: p0, isHuman: true),
    Player(id: 'p1', name: 'P1', stack: p1),
  ],
  deck: Deck(random: Random(seed)),
);

/// Plays the passive action until the flop, where the first actor faces no bet.
void _toFlop(PokerGame g) {
  g.startHand();
  while (g.round == BettingRound.preflop) {
    final p = g.currentPlayer!;
    g.applyAction(
      g.canCheck(p) ? const GameAction.check() : const GameAction.call(),
    );
  }
}

Set<int> _amountsOfType(List<GameAction> a, ActionType t) => {
  for (final x in a.where((x) => x.type == t)) x.amount,
};

void main() {
  group('ActionAbstraction', () {
    test('no bet to face: offers check, pot-fraction bets, and an all-in '
        '(never a fold)', () {
      final game = _headsUp();
      _toFlop(game);
      final hero = game.currentPlayer!; // pot is 20, currentBet 0, stack 990

      final actions = const ActionAbstraction().actionsFor(game, hero);

      expect(actions.any((a) => a.type == ActionType.fold), isFalse);
      expect(actions.where((a) => a.type == ActionType.check), hasLength(1));
      // ½·¾·1× of the 20 pot, plus the 990 shove.
      expect(_amountsOfType(actions, ActionType.bet), {10, 15, 20, 990});
    });

    test(
      'facing a bet: offers fold, call, pot-fraction raises, and an all-in',
      () {
        final game = _headsUp();
        _toFlop(game);
        game.applyAction(const GameAction.bet(20)); // pot-sized bet to 20

        final villain = game.currentPlayer!; // faces 20 to call, pot now 40
        final actions = const ActionAbstraction().actionsFor(game, villain);

        expect(actions.any((a) => a.type == ActionType.fold), isTrue);
        expect(actions.any((a) => a.type == ActionType.call), isTrue);
        // currentBet 20 + ½·¾·1× of the 40 pot, plus the 990 shove.
        expect(_amountsOfType(actions, ActionType.raise), {40, 50, 60, 990});
      },
    );

    test('a short stack facing an over-bet can only fold or call', () {
      final game = _headsUp(p0: 1000, p1: 100);
      game.startHand();
      // p0 (SB) is first to act preflop; raise to more than p1's whole stack.
      expect(game.currentPlayer!.id, 'p0');
      game.applyAction(const GameAction.raise(200));

      final shortStack = game.currentPlayer!; // p1, 90 behind, facing 200
      final actions = const ActionAbstraction().actionsFor(game, shortStack);

      expect(actions.map((a) => a.type).toSet(), {
        ActionType.fold,
        ActionType.call,
      });
    });

    test('every offered action is legal at the position', () {
      final game = _headsUp();
      _toFlop(game);
      final hero = game.currentPlayer!;

      for (final action in const ActionAbstraction().actionsFor(game, hero)) {
        // Applying each candidate to an independent clone must not throw.
        expect(() => game.clone().applyAction(action), returnsNormally);
      }
    });
  });
}
