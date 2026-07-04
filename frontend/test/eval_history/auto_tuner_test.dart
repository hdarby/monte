import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/hand_history.dart';
import 'package:monte/features/eval_history/domain/auto_tuner.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';
import 'package:monte/features/eval_history/domain/profile_overrides.dart';

/// One synthetic hand: a single seat of [model] that either voluntarily plays
/// (a preflop call → VPIP) or folds preflop.
EvalHand _hand(int n, String model, {required bool vpip}) => EvalHand(
  handNumber: n,
  smallBlind: 1,
  bigBlind: 3,
  board: const [],
  players: [
    EvalHandPlayer(
      id: 'p0',
      name: 'x',
      modelId: model,
      modelLabel: model,
      position: 'BB',
      seatsFromButton: 2,
      holeCards: const ['As', 'Ks'],
      startingStack: 300,
      finalStack: vpip ? 300 : 297,
      folded: !vpip,
      foldStreet: vpip ? null : 'preflop',
    ),
  ],
  actions: [
    ActionRecord(
      playerId: 'p0',
      street: BettingRound.preflop,
      type: vpip ? ActionType.call : ActionType.fold,
      amount: 0,
      potAfter: 0,
    ),
  ],
  results: const [],
);

List<EvalHand> _sample(String model, {required int vpipN, required int foldN}) {
  final out = <EvalHand>[];
  var n = 0;
  for (var i = 0; i < vpipN; i++) {
    out.add(_hand(n++, model, vpip: true));
  }
  for (var i = 0; i < foldN; i++) {
    out.add(_hand(n++, model, vpip: false));
  }
  return out;
}

void main() {
  group('AutoTuner.tune', () {
    // Frank Douglas (H005): intended VPIP 0.50.
    final frank = frankDouglas.id;
    final intendedVpip = frankDouglas.strategicBaseline.vpipTarget;

    test('lowers the effective VPIP when a model plays looser than its type', () {
      // Measured 60% vs intended 50% → input should be nudged down.
      final tuned = AutoTuner.tune(
        const ProfileOverrides.empty(),
        _sample(frank, vpipN: 60, foldN: 40),
        minHands: 50,
      );
      final v = tuned.byModel[frank]!.vpipTarget;
      expect(v, lessThan(intendedVpip),
          reason: 'too loose → effective VPIP nudged below target');
    });

    test('leaves the input at target when measured already matches', () {
      // Measured exactly 50% → no VPIP change (starts at intended).
      final tuned = AutoTuner.tune(
        const ProfileOverrides.empty(),
        _sample(frank, vpipN: 50, foldN: 50),
        minHands: 50,
      );
      expect(tuned.byModel[frank]!.vpipTarget, closeTo(intendedVpip, 0.005));
    });

    test('keeps bands nested (3bet ≤ pfr ≤ vpip)', () {
      final tuned = AutoTuner.tune(
        const ProfileOverrides.empty(),
        _sample(frank, vpipN: 70, foldN: 30),
        minHands: 50,
      );
      final b = tuned.byModel[frank]!;
      expect(b.pfrTarget, lessThanOrEqualTo(b.vpipTarget));
      expect(b.threeBetFrequency, lessThanOrEqualTo(b.pfrTarget));
    });

    test('skips models below the minimum-hands threshold', () {
      final tuned = AutoTuner.tune(
        const ProfileOverrides.empty(),
        _sample(frank, vpipN: 12, foldN: 8), // 20 hands
        minHands: 50,
      );
      expect(tuned.byModel.containsKey(frank), isFalse);
    });

    test('skips pros and unknown models (only amateurs are tuned)', () {
      final tuned = AutoTuner.tune(
        const ProfileOverrides.empty(),
        [
          ..._sample(isaacHaxton.id, vpipN: 60, foldN: 40), // a pro
          ..._sample('ZZZ', vpipN: 60, foldN: 40), // unknown
        ],
        minHands: 50,
      );
      expect(tuned.byModel.containsKey(isaacHaxton.id), isFalse);
      expect(tuned.byModel.containsKey('ZZZ'), isFalse);
      expect(tuned.isEmpty, isTrue);
    });
  });
}
