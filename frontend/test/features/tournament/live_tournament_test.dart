import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/features/tournament/data/tournament_controller.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart';
import 'package:monte/features/tournament/domain/tournament_state.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

void main() {
  test('live tournament drives the human table to a finish', () async {
    final c = TournamentController.create(
      structure: TournamentStructure.turbo(
          clockMode: LevelClockMode.hands, startingStack: 400),
      entrants: 12,
      buyIn: 100,
      tableSize: 6,
      seed: 5,
      humanSeat: true,
    );
    addTearDown(c.dispose);

    final tourSnaps = <TournamentSnapshot>[];
    final tableSnaps = <int>[]; // just count table updates
    final done = Completer<void>();

    c.tournamentStream.listen((s) {
      tourSnaps.add(s);
      if (s.finished && !done.isCompleted) done.complete();
    });
    c.tableStream.listen((snap) {
      tableSnaps.add(1);
      // When it's the human's turn, auto-play: check if free, else fold.
      if (snap.currentPlayerId == 'e0' && snap.actionContext != null) {
        final ctx = snap.actionContext!;
        c.submitLiveAction(
            ctx.canCheck ? const GameAction.check() : const GameAction.fold());
      }
    });

    await c.startLive(botDelay: Duration.zero, nextHandDelay: Duration.zero);
    await done.future.timeout(const Duration(seconds: 15));

    expect(c.state.status, TournamentStatus.finished);
    // One champion, all places filled, whole pool paid.
    expect(c.state.players.values.where((p) => p.finishPlace == 1).length, 1);
    expect(
        c.state.players.values.fold(0, (a, p) => a + p.prizeWon), c.state.prizePool);
    // The human got a finish place and we saw live updates for both streams.
    expect(c.state.players['e0']!.finishPlace, isNotNull);
    expect(tableSnaps.length, greaterThan(5));
    expect(tourSnaps.last.finished, isTrue);
    expect(tourSnaps.last.finalResults, isNotNull);
  });
}
