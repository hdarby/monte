// ignore_for_file: avoid_print
//
// End-to-end validation of tool/bench_mcts.dart's per-decision numbers:
// actually run a real 9-handed final table (9 entrants, tableSize 9, so it
// *is* the final table from hand one — tableCount is 1 throughout) to a
// champion with every seat forced onto IsmctsEngine, and report total
// wall-clock and hands played. Run with: `dart run tool/bench_final_table.dart`.
import 'dart:math';

import 'package:monte/core/domain/ai/ismcts.dart';
import 'package:monte/features/tournament/data/tournament_controller.dart';
import 'package:monte/features/tournament/domain/tournament_state.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

void main() {
  const iterationCounts = [100, 250, 500];

  for (final iterations in iterationCounts) {
    final c = TournamentController.create(
      structure: TournamentStructure.turbo(clockMode: LevelClockMode.hands),
      entrants: 9,
      buyIn: 100,
      tableSize: 9,
      seed: 7,
      // No profiles/names → every seat is an anonymous filler, which routes
      // through `deciderBuilder` for all nine — the whole final table plays
      // on IsmctsEngine, not just a subset.
      deciderBuilder: (id, index) => IsmctsEngine(
        config: IsmctsConfig(iterations: iterations),
        random: Random(index),
      ),
    );

    final sw = Stopwatch()..start();
    c.runToCompletion(maxHands: 5000);
    sw.stop();

    final placed = c.state.finishOrder.length; // sanity: everyone placed
    final hands = c.handsPlayed;
    print(
      'iterations=$iterations: ${sw.elapsedMilliseconds}ms wall-clock, '
      'status=${c.state.status}, players placed=$placed, hands played=$hands '
      '(${(sw.elapsedMilliseconds / hands).toStringAsFixed(1)}ms/hand average)',
    );
    c.dispose();
  }
}
