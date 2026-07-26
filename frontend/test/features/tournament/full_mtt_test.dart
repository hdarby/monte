import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/tournament/data/tournament_controller.dart';
import 'package:monte/features/tournament/domain/tournament_state.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

TournamentController _mtt(int seed, {int entrants = 18, int tableSize = 6}) =>
    TournamentController.create(
      structure: TournamentStructure.turbo(
          clockMode: LevelClockMode.hands, startingStack: 1500),
      entrants: entrants,
      buyIn: 100,
      tableSize: tableSize,
      seed: seed,
    );

void main() {
  group('full multi-table MTT', () {
    test('runs to a single champion with a complete, paid finish order', () {
      final c = _mtt(1);
      c.runToCompletion();

      final s = c.state;
      expect(s.status, TournamentStatus.finished);
      expect(s.playersRemaining, 1);

      // Everyone has a finish place, exactly one champion, all distinct 1..N.
      final places = s.players.values.map((p) => p.finishPlace).toList();
      expect(places.every((p) => p != null), isTrue);
      expect(places.toSet().length, s.entrants); // all distinct
      expect(places.where((p) => p == 1).length, 1);
      expect(s.finishOrder.length, s.entrants);

      // The whole prize pool is paid out, and only paid places win.
      final paid = s.players.values.fold(0, (a, p) => a + p.prizeWon);
      expect(paid, s.prizePool);
      for (final p in s.players.values) {
        if (p.prizeWon > 0) {
          expect(p.finishPlace, lessThanOrEqualTo(s.paidPlaces));
        }
      }
    });

    test('conserves chips: total chips always equals entrants x starting stack', () {
      final c = _mtt(2);
      const expected = 18 * 1500;
      c.onRound = () {
        final total = c.state.players.values.fold(0, (a, p) => a + p.chips);
        expect(total, expected);
      };
      c.runToCompletion();
    });

    test('never lets table sizes differ by more than one', () {
      final c = _mtt(3);
      c.onRound = () {
        final sizes = [
          for (final t in c.state.tables)
            if (t.size > 0) t.size,
        ];
        if (sizes.length > 1) {
          sizes.sort();
          expect(sizes.last - sizes.first, lessThanOrEqualTo(1));
        }
      };
      c.runToCompletion();
    });

    test('is fully deterministic for a given seed', () {
      List<String?> run() {
        final c = _mtt(7);
        c.runToCompletion();
        final players = c.state.players.values.toList()
          ..sort((a, b) => a.id.compareTo(b.id));
        return [for (final p in players) '${p.id}:${p.finishPlace}:${p.prizeWon}'];
      }

      expect(run(), run());
    });
  });
}
