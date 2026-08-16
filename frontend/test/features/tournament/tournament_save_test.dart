import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/features/tournament/data/tournament_save_store.dart';
import 'package:monte/features/tournament/data/tournament_controller.dart';
import 'package:monte/features/tournament/domain/tournament_save.dart';
import 'package:monte/features/tournament/domain/tournament_state.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

/// Saving is taken at a hand boundary: the hand in flight is deliberately not
/// serialised, so a reload deals fresh from the saved chip counts, seats and
/// level. What must survive is everything that makes it *this* tournament —
/// who is left, how many chips each has, which table they sit at, what level it
/// is, and which personalities are in the field.
TournamentController _running({int hands = 40, int entrants = 18}) {
  final c = TournamentController.create(
    structure: TournamentStructure.wsopCircuit(clockMode: LevelClockMode.hands),
    entrants: entrants,
    buyIn: 500,
    tableSize: 9,
    seed: 21,
    humanSeat: true,
    names: ['You', for (var i = 1; i < entrants; i++) 'Bot $i'],
    botProfiles: [
      for (var i = 0; i < entrants - 1; i++)
        builtInProfiles[i % builtInProfiles.length],
    ],
  );
  for (var i = 0; i < hands && c.state.status == TournamentStatus.running; i++) {
    c.step();
  }
  return c;
}

void main() {
  group('capturing a tournament', () {
    test('records the field as it stands', () {
      final c = _running();
      final save = c.saveAs('Friday night');

      expect(save.name, 'Friday night');
      expect(save.players.length, c.state.entrants);
      expect(save.buyIn, c.state.buyIn);
      expect(save.levelIndex, c.state.levelIndex);
      expect(save.prizePool, c.state.prizePool);
      // Chips are the point of the exercise.
      for (final sp in save.players) {
        expect(sp.chips, c.state.players[sp.id]!.chips,
            reason: '${sp.id} chips drifted');
        expect(sp.status, c.state.players[sp.id]!.status.name);
      }
      // And the personalities, so the same field comes back.
      expect(save.profileIds, isNotEmpty);
      c.dispose();
    });

    test('survives a JSON round trip unchanged', () {
      final c = _running();
      final original = c.saveAs('Round trip');
      final copy = TournamentSave.fromJson(original.toJson());

      expect(copy.name, original.name);
      expect(copy.seed, original.seed);
      expect(copy.levelIndex, original.levelIndex);
      expect(copy.tableSize, original.tableSize);
      expect(copy.status, original.status);
      expect(copy.finishOrder, original.finishOrder);
      expect(copy.profileIds, original.profileIds);
      expect(copy.payoutFractions, original.payoutFractions);
      expect(copy.players.map((p) => p.chips).toList(),
          original.players.map((p) => p.chips).toList());
      expect(copy.tables.map((t) => t.playerIds).toList(),
          original.tables.map((t) => t.playerIds).toList());
      c.dispose();
    });

    test('the label carries a datestamp', () {
      final c = _running(hands: 5);
      final save = c.saveAs('Main', at: DateTime(2026, 8, 15, 14, 32));
      expect(save.label, 'Main — 2026-08-15 14:32');
      expect(save.id, 'Main_20260815_143200');
      c.dispose();
    });

    test('the id is safe to use as a filename', () {
      final c = _running(hands: 5);
      final save = c.saveAs('Sunday / Major: "big" one');
      expect(save.id, isNot(contains('/')));
      expect(save.id, isNot(contains('"')));
      expect(save.id, isNot(contains(':')));
      c.dispose();
    });
  });

  group('resuming one', () {
    test('comes back with the same chips, seats and level', () {
      final c = _running();
      final save = c.saveAs('Resume me');
      final before = {
        for (final p in c.state.players.values) p.id: p.chips,
      };
      final level = c.state.levelIndex;
      final remaining = c.state.playersRemaining;
      c.dispose();

      final resumed = TournamentController.restore(save);
      expect(resumed.state.levelIndex, level);
      expect(resumed.state.playersRemaining, remaining,
          reason: 'the active count must be right, not stale');
      for (final e in before.entries) {
        expect(resumed.state.players[e.key]!.chips, e.value,
            reason: '${e.key} came back with the wrong stack');
      }
      // Seating is restored rather than redrawn.
      expect(
        resumed.state.tables.map((t) => t.playerIds).toList(),
        save.tables.map((t) => t.playerIds).toList(),
      );
      resumed.dispose();
    });

    test('brings back the same personalities, not a fresh field', () {
      final c = _running();
      final save = c.saveAs('Same faces');
      final before = c.profileBySeat.map((k, v) => MapEntry(k, v.id));
      c.dispose();

      final resumed = TournamentController.restore(save);
      final after = resumed.profileBySeat.map((k, v) => MapEntry(k, v.id));
      expect(after, before);
      resumed.dispose();
    });

    test('keeps playing from where it left off', () {
      final c = _running();
      final save = c.saveAs('Carry on');
      c.dispose();

      final resumed = TournamentController.restore(save);
      final startLevel = resumed.state.levelIndex;
      for (var i = 0; i < 60 && resumed.state.status == TournamentStatus.running; i++) {
        resumed.step();
      }
      expect(resumed.state.levelIndex, greaterThanOrEqualTo(startLevel));
      // Chips are conserved: nothing was invented or lost by the round trip.
      final total = resumed.state.players.values
          .fold<int>(0, (a, p) => a + p.chips);
      final expected = save.players.fold<int>(0, (a, p) => a + p.chips);
      expect(total, expected);
      resumed.dispose();
    });

    test('an unknown blind structure is refused rather than guessed', () {
      final c = _running(hands: 5);
      final save = c.saveAs('Bad structure');
      final broken = TournamentSave.fromJson({
        ...save.toJson(),
        'structureName': 'not-a-real-preset',
      });
      expect(() => TournamentController.restore(broken), throwsStateError);
      c.dispose();
    });
  });

  group('the store', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('monte_saves'));
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('lists newest first, loads back, deletes one and deletes all',
        () async {
      final store = FileTournamentSaveStore(dir);
      expect(await store.list(), isEmpty);

      final c = _running(hands: 10);
      final older = c.saveAs('Older', at: DateTime(2026, 1, 1, 10));
      final newer = c.saveAs('Newer', at: DateTime(2026, 8, 15, 10));
      c.dispose();

      await store.save(older);
      await store.save(newer);

      final listed = await store.list();
      expect(listed.map((s) => s.name), ['Newer', 'Older'],
          reason: 'newest first');
      expect(listed.first.players.length, newer.players.length);

      await store.delete(older.id);
      expect((await store.list()).map((s) => s.name), ['Newer']);

      await store.deleteAll();
      expect(await store.list(), isEmpty);
    });

    test('deleting something already gone is harmless', () async {
      final store = FileTournamentSaveStore(dir);
      await store.delete('nothing');
      await store.deleteAll();
      expect(await store.list(), isEmpty);
    });

    test('a corrupt save does not take the whole list down', () async {
      final store = FileTournamentSaveStore(dir);
      final c = _running(hands: 5);
      await store.save(c.saveAs('Good'));
      c.dispose();

      final saves = Directory('${dir.path}${Platform.pathSeparator}tournaments');
      File('${saves.path}${Platform.pathSeparator}broken.tourney.json')
          .writeAsStringSync('{ not json at all');

      final listed = await store.list();
      expect(listed.map((s) => s.name), ['Good']);
    });
  });
}
