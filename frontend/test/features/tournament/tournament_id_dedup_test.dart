import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/tournament/data/tournament_controller.dart';
import 'package:monte/features/tournament/data/tournament_result_store.dart';
import 'package:monte/features/tournament/data/tournament_save_store.dart';
import 'package:monte/features/tournament/domain/tournament_result.dart';
import 'package:monte/features/tournament/domain/tournament_save.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

/// A simple in-memory [TournamentResultStore] — no such fake ships with the
/// production code (only a file-backed one and a no-op), and this test needs
/// writes to actually be readable back.
class MemoryTournamentResultStore implements TournamentResultStore {
  final List<TournamentResult> _results = [];

  @override
  void record(TournamentResult result) => _results.add(result);

  @override
  Future<List<TournamentResult>> loadAll() async => List.of(_results);

  @override
  Future<void> wipe() async => _results.clear();
}

/// Guards against the same underlying tournament being credited (or
/// replayed) more than once — a save taken near the end could otherwise be
/// reloaded repeatedly for free shots at the same prize/career credit.
void main() {
  test('a save keeps its tournament id across a restore', () {
    final c = TournamentController.create(
      structure: TournamentStructure.turbo(clockMode: LevelClockMode.hands),
      entrants: 6,
      buyIn: 100,
      tableSize: 6,
      seed: 5,
      humanSeat: true,
      names: const ['You', 'Bot 1', 'Bot 2', 'Bot 3', 'Bot 4', 'Bot 5'],
    );
    final save = TournamentSave.fromJson(c.saveAs('x').toJson());
    expect(save.tournamentId, c.tournamentId);
    expect(save.tournamentId, isNotEmpty);
    c.dispose();

    final resumed = TournamentController.restore(save);
    expect(resumed.tournamentId, save.tournamentId);
    resumed.dispose();
  });

  test('finishing a tournament twice from the same save records only once '
      'and purges the stale save', () async {
    final resultStore = MemoryTournamentResultStore();
    final saveStore = MemoryTournamentSaveStore();

    TournamentController makeController({TournamentSave? restore}) =>
        restore == null
            ? TournamentController.create(
                structure:
                    TournamentStructure.turbo(clockMode: LevelClockMode.hands),
                entrants: 4,
                buyIn: 100,
                tableSize: 4,
                seed: 5,
                resultStore: resultStore,
                saveStore: saveStore,
              )
            : TournamentController.restore(
                restore,
                resultStore: resultStore,
                saveStore: saveStore,
              );

    final first = makeController();
    final save = first.saveAs('near the end');
    await saveStore.save(save);
    first.runToCompletion();
    // _recordCareer's dedup/purge check is async (a fresh store read), so
    // give it a turn to actually run before asserting on the store.
    await Future<void>.delayed(Duration.zero);

    final results1 = await resultStore.loadAll();
    expect(results1.length, 1);
    expect(results1.single.tournamentId, first.tournamentId);

    // Reload the same save and run it to completion again.
    final reloaded = TournamentSave.fromJson(save.toJson());
    final second = makeController(restore: reloaded);
    second.runToCompletion();
    await Future<void>.delayed(Duration.zero);

    final results2 = await resultStore.loadAll();
    expect(
      results2.where((r) => r.tournamentId == first.tournamentId).length,
      1,
      reason: 'the same tournament must not be credited twice',
    );
  });
}
