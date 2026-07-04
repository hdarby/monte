import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/eval_history/data/file_eval_history_store.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';

EvalHand _hand(int n) => EvalHand(
  handNumber: n,
  smallBlind: 1,
  bigBlind: 3,
  board: const ['Ah', 'Kd', '2c'],
  players: [
    EvalHandPlayer(
      id: 'bot_0',
      name: 'M$n',
      modelId: 'H001',
      modelLabel: 'M$n',
      position: 'BTN',
      seatsFromButton: 0,
      holeCards: const ['As', 'Ks'],
      startingStack: 300,
      finalStack: 312,
      folded: false,
    ),
  ],
  actions: const [],
  results: const [],
);

void main() {
  group('FileEvalHistoryStore', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('eval_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('record → flush → loadAll round-trips, preserving order', () async {
      final store = FileEvalHistoryStore(dir);
      store.record(_hand(1));
      store.record(_hand(2));
      await store.flush();

      final loaded = await store.loadAll();
      expect(loaded.map((h) => h.handNumber), [1, 2]);
      expect(loaded.first.players.single.holeCards, ['As', 'Ks']);
      expect(await store.count(), 2);
    });

    test('persists across a reopen of the same directory', () async {
      final a = FileEvalHistoryStore(dir);
      a.record(_hand(1));
      await a.flush();

      final b = FileEvalHistoryStore(dir);
      expect(await b.count(), 1);
      expect((await b.loadAll()).single.handNumber, 1);
    });

    test('wipe empties the record', () async {
      final store = FileEvalHistoryStore(dir);
      store.record(_hand(1));
      await store.flush();
      expect(await store.count(), 1);

      await store.wipe();
      expect(await store.count(), 0);
      expect(await store.loadAll(), isEmpty);

      // A fresh store over the same dir sees nothing either.
      expect(await FileEvalHistoryStore(dir).count(), 0);
    });

    test('records survive after wipe when new hands are added', () async {
      final store = FileEvalHistoryStore(dir);
      store.record(_hand(1));
      await store.wipe();
      store.record(_hand(2));
      await store.flush();

      final loaded = await store.loadAll();
      expect(loaded.map((h) => h.handNumber), [2]);
    });
  });
}
