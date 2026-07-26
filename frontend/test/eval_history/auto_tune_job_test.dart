import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/hand_history.dart';
import 'package:monte/features/eval_history/data/file_eval_history_store.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';
import 'package:monte/features/eval_history/presentation/auto_tune_job.dart';
import 'package:monte/features/eval_history/presentation/eval_history_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// One synthetic hand: a single seat of [model] that voluntarily plays (a preflop
// call → VPIP) or folds preflop.
EvalHand _hand(int n, String model, {required bool vpip}) => EvalHand(
      handNumber: n,
      smallBlind: 1,
      bigBlind: 3,
      board: const [],
      players: [
        EvalHandPlayer(
          id: 'p0', name: 'x', modelId: model, modelLabel: model,
          position: 'BB', seatsFromButton: 2, holeCards: const ['As', 'Ks'],
          startingStack: 300, finalStack: vpip ? 300 : 297,
          folded: !vpip, foldStreet: vpip ? null : 'preflop',
        ),
      ],
      actions: [
        ActionRecord(
          playerId: 'p0', street: BettingRound.preflop,
          type: vpip ? ActionType.call : ActionType.fold, amount: 0, potAfter: 0,
        ),
      ],
      results: const [],
    );

List<EvalHand> _sample(String model, {required int vpipN, required int foldN}) => [
      for (var i = 0; i < vpipN; i++) _hand(i, model, vpip: true),
      for (var i = 0; i < foldN; i++) _hand(vpipN + i, model, vpip: false),
    ];

/// In-memory store the job can read/consume.
class _FakeStore implements EvalHistoryStore {
  _FakeStore(this._hands);
  List<EvalHand> _hands;
  bool wiped = false;

  @override
  void record(EvalHand hand) => _hands.add(hand);
  @override
  Future<void> flush() async {}
  @override
  Future<List<EvalHand>> loadAll() async => _hands;
  @override
  Future<int> count() async => _hands.length;
  @override
  Future<void> wipe() async {
    _hands = [];
    wiped = true;
  }
}

ProviderContainer _container(_FakeStore store) {
  final c = ProviderContainer(
    overrides: [evalHistoryStoreProvider.overrideWithValue(store)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AutoTuneJob.runIfReady', () {
    final frank = frankDouglas.id; // a home-game amateur that gets tuned

    test('tunes and consumes the sample once enough history has accumulated', () async {
      // 350 hands at ~57% VPIP vs Frank's intended 50% → the tuner nudges him.
      final store = _FakeStore(_sample(frank, vpipN: 200, foldN: 150));
      final c = _container(store);

      final changed = await c.read(autoTuneJobProvider.notifier).runIfReady();

      expect(changed, greaterThan(0), reason: 'a qualifying model is tuned');
      expect(store.wiped, isTrue, reason: 'the consumed sample is wiped');
      expect(c.read(autoTuneJobProvider).runs, 1);
      expect(c.read(autoTuneJobProvider).lastConsumed, 350);
    });

    test('does nothing while there is too little history to bring in', () async {
      final store = _FakeStore(_sample(frank, vpipN: 30, foldN: 20)); // 50 < 300
      final c = _container(store);

      final changed = await c.read(autoTuneJobProvider.notifier).runIfReady();

      expect(changed, 0);
      expect(store.wiped, isFalse, reason: 'nothing consumed below the threshold');
      expect(c.read(autoTuneJobProvider).runs, 0);
    });
  });
}
