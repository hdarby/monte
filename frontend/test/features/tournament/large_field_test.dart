import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/tournament/data/tournament_controller.dart';
import 'package:monte/features/tournament/domain/tournament_state.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

/// Large multi-table fields now play out with a real hand at every table each
/// round (no statistical shortcut), so chips are conserved by actual play. These
/// use a fast, shallow structure so a big field still resolves headless in a few
/// seconds; the deep WSOP structures are validated live (see
/// live_conservation_test) rather than ground out to a champion headless.
void main() {
  void runField({required int entrants}) {
    test('$entrants runners resolve headless, chips conserved every round', () {
      final structure =
          TournamentStructure.turbo(clockMode: LevelClockMode.hands);
      final c = TournamentController.create(
        structure: structure,
        entrants: entrants,
        buyIn: 100,
        tableSize: 9,
        seed: 1,
      );
      final total = entrants * structure.startingStack;
      c.onRound = () {
        // Real hands only move chips between players at a table — the field
        // total never drifts.
        expect(c.state.players.values.fold(0, (a, p) => a + p.chips), total);
      };
      c.runToCompletion();

      final s = c.state;
      expect(s.status, TournamentStatus.finished);
      expect(s.players.values.where((p) => p.finishPlace == 1).length, 1);
      expect(s.finishOrder.length, entrants); // everyone placed
      expect(s.players.values.fold(0, (a, p) => a + p.prizeWon), s.prizePool);
      for (final p in s.players.values) {
        if (p.prizeWon > 0) {
          expect(p.finishPlace, lessThanOrEqualTo(s.paidPlaces));
        }
      }
    });
  }

  runField(entrants: 240); // 27 tables
  runField(entrants: 500); // 56 tables
}
