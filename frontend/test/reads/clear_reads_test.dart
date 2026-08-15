import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/player_stats.dart';
import 'package:monte/features/reads/data/player_stats_store.dart';

/// Reads are observed statistics accumulated across sessions and keyed to a
/// personality's durable id. When the bots' decision logic changes, everything
/// gathered under the old behaviour describes a game that no longer exists —
/// and an exploitative bot will happily keep acting on it. Settings → Opponent
/// reads → Clear is the reset, so the wipe has to actually reach the disk.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('monte_reads'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File fileIn(Directory d) =>
      File('${d.path}${Platform.pathSeparator}opponent_stats.json');

  test('a wipe removes the persisted file, not just the in-memory book',
      () async {
    final store = FilePlayerStatsStore(dir);
    final stats = PlayerStats()
      ..hands = 240
      ..betFaced = 100
      ..foldToBet = 62;
    expect(stats.established, isTrue);
    final book = PlayerStatsBook({'P001': stats});

    await store.save(book);
    expect(fileIn(dir).existsSync(), isTrue, reason: 'reads should persist');

    final service = OpponentStatsService(store, book);
    await service.wipe();

    expect(fileIn(dir).existsSync(), isFalse,
        reason: 'the stale file must be gone from disk');
    expect(service.book.read('P001'), isNull,
        reason: 'and the loaded book must be empty too');
  });

  test('a reload after wiping sees no reads at all', () async {
    final store = FilePlayerStatsStore(dir);
    final book = PlayerStatsBook({'P001': PlayerStats()..hands = 240});
    await store.save(book);

    await OpponentStatsService(store, book).wipe();

    // A fresh service, as the app would build on next launch.
    final reloaded = await OpponentStatsService.load(FilePlayerStatsStore(dir));
    expect(reloaded.book.read('P001'), isNull,
        reason: 'nothing carried over, so no exploit fires on stale data');
    expect(reloaded.book.ids, isEmpty);
  });

  test('wiping an already-clean store is harmless', () async {
    final service =
        await OpponentStatsService.load(FilePlayerStatsStore(dir));
    await service.wipe();
    await service.wipe();
    expect(fileIn(dir).existsSync(), isFalse);
  });
}
