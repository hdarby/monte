// ignore_for_file: avoid_print
//
// Answers: at what table count does the MCTS cutover stop being "one live
// table's opponents" and become "several background tables blocking a
// round"? `step()` plays one hand at every remaining table synchronously —
// that's the unit of work that has to complete before the next thing the
// human sees (the next hand dealt, or the next background round) happens.
// Times `step()` at increasing table counts with every seat forced onto
// IsmctsEngine at 500 iterations (the tier picked from bench_final_table.dart).
// Run with: `dart run tool/bench_multi_table.dart`.
import 'dart:math';

import 'package:monte/core/domain/ai/ismcts.dart';
import 'package:monte/features/tournament/data/tournament_controller.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

void main() {
  const iterations = 500;
  const tableCounts = [1, 2, 3, 4, 5, 6];
  const roundsToTime = 5;

  print(
    'step() cost at $iterations MCTS iterations/decision, every seat forced '
    'onto the search backend — $roundsToTime rounds averaged per table count\n',
  );

  for (final tables in tableCounts) {
    final entrants = tables * 9;
    final c = TournamentController.create(
      structure: TournamentStructure.turbo(clockMode: LevelClockMode.hands),
      entrants: entrants,
      buyIn: 100,
      tableSize: 9,
      seed: 11,
      deciderBuilder: (id, index) => IsmctsEngine(
        config: IsmctsConfig(iterations: iterations),
        random: Random(index),
      ),
    );

    final times = <int>[];
    for (var r = 0; r < roundsToTime; r++) {
      if (c.state.status.name == 'finished') break;
      final sw = Stopwatch()..start();
      c.step();
      sw.stop();
      times.add(sw.elapsedMilliseconds);
    }
    final avg = times.isEmpty
        ? double.nan
        : times.reduce((a, b) => a + b) / times.length;
    print(
      'tables=$tables ($entrants players): avg ${avg.toStringAsFixed(0)}ms/'
      'round over ${times.length} rounds — per-table ~'
      '${(avg / tables).toStringAsFixed(1)}ms',
    );
    c.dispose();
  }

  print(
    '\nThis is the added latency a live final table (or the background '
    'field, once step() is called between the human\'s hands) blocks for, '
    'once per round. Compare against a UX bar for "the game feels '
    'responsive."',
  );
}
