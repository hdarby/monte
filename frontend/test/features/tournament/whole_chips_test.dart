import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/tournament/data/tournament_controller.dart';
import 'package:monte/features/tournament/domain/chip_set.dart';
import 'package:monte/features/tournament/domain/tournament_state.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

void main() {
  test('no stack is ever a fraction of the smallest chip in play', () {
    final chips = ChipSet.wsop();
    for (final seed in [1, 2, 3, 7, 42]) {
      final c = TournamentController.create(
        structure: TournamentStructure.turbo(clockMode: LevelClockMode.hands),
        entrants: 27,
        buyIn: 100,
        tableSize: 6,
        seed: seed,
      );
      c.onRound = () {
        final level = c.state.currentLevel;
        final unit = chips.smallestChip(
          smallBlind: level.smallBlind,
          bigBlind: level.bigBlind,
          ante: level.ante,
        );
        for (final p in c.state.players.values) {
          expect(p.chips % unit, 0,
              reason: 'seed $seed: ${p.name} has ${p.chips}, not a multiple '
                  'of the $unit chip');
        }
      };
      c.runToCompletion();
      expect(c.state.status, TournamentStatus.finished);
    }
  });

  test('large multi-table field never leaves a fractional chip', () {
    final chips = ChipSet.wsop();
    final base = chips.denominations.first;
    for (final seed in [1, 4]) {
      final c = TournamentController.create(
        structure: TournamentStructure.turbo(clockMode: LevelClockMode.hands),
        entrants: 300,
        buyIn: 1000,
        tableSize: 9,
        seed: seed,
      );
      c.onRound = () {
        for (final p in c.state.players.values) {
          expect(p.chips % base, 0,
              reason: 'seed $seed: ${p.name} has ${p.chips}, '
                  'not a whole $base chip');
        }
      };
      c.runToCompletion();
      expect(c.state.status, TournamentStatus.finished);
    }
  });
}
