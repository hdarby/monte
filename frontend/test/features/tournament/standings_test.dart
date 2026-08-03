import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/tournament/data/tournament_controller.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

void main() {
  test('standings lists every player: active by chips, busted by finish', () {
    final c = TournamentController.create(
      structure: TournamentStructure.turbo(clockMode: LevelClockMode.hands),
      entrants: 18,
      buyIn: 100,
      tableSize: 6,
      seed: 3,
    );
    // Play some hands so a few players bust.
    for (var i = 0; i < 40 && c.state.playersRemaining > 6; i++) {
      c.step();
    }

    final rows = c.standings();
    // Every entrant appears exactly once, places are 1..entrants contiguous.
    expect(rows.length, 18);
    expect(rows.map((r) => r.place).toSet(), {for (var p = 1; p <= 18; p++) p});

    // Active players (not busted) come first and are sorted by chips desc.
    final active = rows.where((r) => !r.busted).toList();
    for (var i = 1; i < active.length; i++) {
      expect(active[i - 1].chips, greaterThanOrEqualTo(active[i].chips));
    }
    // Busted players are all below the last active player.
    final lastActiveIndex = rows.lastIndexWhere((r) => !r.busted);
    final firstBustedIndex = rows.indexWhere((r) => r.busted);
    if (firstBustedIndex >= 0) {
      expect(firstBustedIndex, greaterThan(lastActiveIndex - 1));
      expect(lastActiveIndex, lessThan(firstBustedIndex));
    }
  });
}
