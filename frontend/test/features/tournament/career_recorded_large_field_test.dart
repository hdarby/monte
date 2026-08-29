import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/features/tournament/data/tournament_controller.dart';
import 'package:monte/features/tournament/data/tournament_result_store.dart';
import 'package:monte/features/tournament/domain/tournament_result.dart';
import 'package:monte/features/tournament/domain/tournament_state.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

class _FakeStore implements TournamentResultStore {
  final List<TournamentResult> results = [];
  @override
  void record(TournamentResult result) => results.add(result);
  @override
  Future<List<TournamentResult>> loadAll() async => results;
  @override
  Future<void> wipe() async => results.clear();
}

/// Regression for a bug where a large field (more than `_finishHeadless`'s
/// `resolveBelow` threshold of 72 players still in when the human busts)
/// never wrote a career record at all: `_settleByChips` — the shortcut used
/// to resolve a big unwatched field instantly by chip count instead of
/// grinding it out hand by hand — called `state.declareChampion()` directly,
/// bypassing `_maybeFinish()` and the `_recordCareer()` call inside it. A
/// small field always went through the hand-by-hand `step()` loop, which
/// does call `_maybeFinish()`, so this only ever showed up on a big field —
/// exactly what "play a tournament with every personality" produces.
void main() {
  test('a large field the human busts out of still records a career result',
      () async {
    final store = _FakeStore();
    final c = TournamentController.create(
      structure: TournamentStructure.turbo(
          clockMode: LevelClockMode.hands, startingStack: 400),
      entrants: 200,
      buyIn: 100,
      tableSize: 9,
      seed: 5,
      humanSeat: true,
      resultStore: store,
    );
    addTearDown(c.dispose);

    final done = Completer<void>();
    c.tournamentStream.listen((s) {
      if (s.finished && !done.isCompleted) done.complete();
    });
    c.tableStream.listen((snap) {
      // Fold at every opportunity so the human busts out quickly, well
      // before the field is anywhere near resolveBelow (72) players left.
      if (snap.currentPlayerId == 'e0' && snap.actionContext != null) {
        final ctx = snap.actionContext!;
        c.submitLiveAction(
            ctx.canCheck ? const GameAction.check() : const GameAction.fold());
      }
    });

    await c.startLive(botDelay: Duration.zero);
    await done.future.timeout(const Duration(seconds: 30));

    expect(c.state.status, TournamentStatus.finished);
    expect(store.results, hasLength(1));
    expect(store.results.single.entrants, 200);
    expect(
      store.results.single.finishes.where((f) => f.isHuman).single.place,
      greaterThan(0),
    );
  });
}
