import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/hand_history.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';

EvalHand _sample() => EvalHand(
  handNumber: 7,
  smallBlind: 1,
  bigBlind: 3,
  board: const ['Ah', 'Kd', '2c', '7s', '9h'],
  players: [
    const EvalHandPlayer(
      id: 'bot_0',
      name: 'Phil DiPinto',
      modelId: 'H008',
      modelLabel: 'Phil DiPinto',
      position: 'BTN',
      seatsFromButton: 0,
      holeCards: ['As', 'Ks'],
      startingStack: 300,
      finalStack: 360,
      folded: false,
      madeHand: 'Pair',
      skill: 0.71,
      vpipTarget: 0.24,
      pfrTarget: 0.19,
      threeBetTarget: 0.06,
    ),
    const EvalHandPlayer(
      id: 'bot_1',
      name: 'Frank Douglas',
      modelId: 'H005',
      modelLabel: 'Frank Douglas',
      position: 'BB',
      seatsFromButton: 2,
      holeCards: ['7d', '2h'], // full — even though he folded
      startingStack: 300,
      finalStack: 240,
      folded: true,
      foldStreet: 'flop',
    ),
  ],
  actions: const [
    ActionRecord(
      playerId: 'bot_0',
      street: BettingRound.preflop,
      type: ActionType.raise,
      amount: 9,
      potAfter: 13,
    ),
    ActionRecord(
      playerId: 'bot_1',
      street: BettingRound.flop,
      type: ActionType.fold,
      amount: 0,
      potAfter: 13,
    ),
  ],
  results: const [
    HandResultRecord(playerId: 'bot_0', amountWon: 13, handRank: 'Pair'),
  ],
);

void main() {
  group('EvalHand', () {
    test('round-trips through JSON with full (unmasked) cards', () {
      final decoded = EvalHand.fromJson(_sample().toJson());

      expect(decoded.handNumber, 7);
      expect(decoded.board, hasLength(5));
      expect(decoded.actions, hasLength(2));
      expect(decoded.actions.first.type, ActionType.raise);
      expect(decoded.results.single.playerId, 'bot_0');

      final phil = decoded.players[0];
      expect(phil.holeCards, ['As', 'Ks']);
      expect(phil.modelId, 'H008');
      expect(phil.position, 'BTN');
      expect(phil.vpipTarget, 0.24);
      expect(phil.net, 60);

      // A folded player still carries full cards in the tuning record.
      final frank = decoded.players[1];
      expect(frank.folded, isTrue);
      expect(frank.foldStreet, 'flop');
      expect(frank.holeCards, ['7d', '2h']);
      expect(frank.net, -60);
    });

    test('positionLabel maps seats to poker positions', () {
      // Heads-up: the button is the small blind.
      expect(positionLabel(0, 2), 'SB');
      expect(positionLabel(1, 2), 'BB');

      // 6-max around the button.
      expect(positionLabel(0, 6), 'BTN');
      expect(positionLabel(1, 6), 'SB');
      expect(positionLabel(2, 6), 'BB');
      expect(positionLabel(3, 6), 'UTG');
      expect(positionLabel(5, 6), 'CO');
    });
  });
}
