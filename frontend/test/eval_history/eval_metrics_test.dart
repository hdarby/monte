import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/hand_history.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';
import 'package:monte/features/eval_history/domain/eval_metrics.dart';

EvalHandPlayer _pl(
  String id,
  String model,
  String pos, {
  bool folded = false,
  String? foldStreet,
  int finalStack = 300,
}) => EvalHandPlayer(
  id: id,
  name: id,
  modelId: model,
  modelLabel: model,
  position: pos,
  seatsFromButton: 0,
  holeCards: const ['As', 'Ks'],
  startingStack: 300,
  finalStack: finalStack,
  folded: folded,
  foldStreet: foldStreet,
);

ActionRecord _ac(String id, BettingRound street, ActionType type) =>
    ActionRecord(playerId: id, street: street, type: type, amount: 0, potAfter: 0);

void main() {
  group('EvalMetrics.byModel', () {
    test('a folded-around late raise is a successful steal', () {
      final hand = EvalHand(
        handNumber: 1,
        smallBlind: 1,
        bigBlind: 3,
        board: const [], // ended preflop
        players: [
          _pl('p0', 'STEAL', 'BTN', finalStack: 304),
          _pl('p1', 'X', 'SB', folded: true, foldStreet: 'preflop'),
          _pl('p2', 'X', 'BB', folded: true, foldStreet: 'preflop'),
        ],
        actions: [
          _ac('p0', BettingRound.preflop, ActionType.raise),
          _ac('p1', BettingRound.preflop, ActionType.fold),
          _ac('p2', BettingRound.preflop, ActionType.fold),
        ],
        results: const [
          HandResultRecord(playerId: 'p0', amountWon: 4),
        ],
      );

      final m = EvalMetrics.byModel([hand])['STEAL']!;
      expect(m.hands, 1);
      expect(m.vpip, 100);
      expect(m.pfr, 100);
      expect(m.stealAttemptPct, 100);
      expect(m.stealSuccessPct, 100);
    });

    test('a first-in call with no raise is a limp (VPIP, not PFR)', () {
      final hand = EvalHand(
        handNumber: 2,
        smallBlind: 1,
        bigBlind: 3,
        board: const ['Ah', 'Kd', '2c', '7s', '9h'],
        players: [
          _pl('p0', 'LIMP', 'UTG'),
          _pl('p1', 'X', 'BB'),
        ],
        actions: [
          _ac('p0', BettingRound.preflop, ActionType.call),
          _ac('p1', BettingRound.preflop, ActionType.check),
          _ac('p0', BettingRound.flop, ActionType.check),
          _ac('p1', BettingRound.flop, ActionType.check),
        ],
        results: const [],
      );

      final m = EvalMetrics.byModel([hand])['LIMP']!;
      expect(m.hands, 1);
      expect(m.vpip, 100);
      expect(m.limp, 100);
      expect(m.pfr, 0);
      expect(m.stealAttemptPct, 0); // UTG is not a steal seat
    });

    test('folding to a river bet counts as fold-to-river', () {
      final hand = EvalHand(
        handNumber: 3,
        smallBlind: 1,
        bigBlind: 3,
        board: const ['Ah', 'Kd', '2c', '7s', '9h'],
        players: [
          _pl('p0', 'RVR', 'BB', folded: true, foldStreet: 'river', finalStack: 291),
          _pl('p1', 'X', 'BTN', finalStack: 309),
        ],
        actions: [
          _ac('p1', BettingRound.preflop, ActionType.raise),
          _ac('p0', BettingRound.preflop, ActionType.call),
          _ac('p0', BettingRound.flop, ActionType.check),
          _ac('p1', BettingRound.flop, ActionType.check),
          _ac('p0', BettingRound.turn, ActionType.check),
          _ac('p1', BettingRound.turn, ActionType.check),
          _ac('p1', BettingRound.river, ActionType.bet),
          _ac('p0', BettingRound.river, ActionType.fold),
        ],
        results: const [
          HandResultRecord(playerId: 'p1', amountWon: 18),
        ],
      );

      final m = EvalMetrics.byModel([hand])['RVR']!;
      expect(m.hands, 1);
      expect(m.vpip, 100); // called preflop
      expect(m.limp, 0); // faced a raise
      expect(m.riverSeen, 1);
      expect(m.foldToRiverBet, 100);
    });
  });
}
