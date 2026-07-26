import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

void main() {
  group('TournamentStructure presets', () {
    test('presets are ordered ladders with antes kicking in later', () {
      for (final s in [
        TournamentStructure.turbo(),
        TournamentStructure.standard(),
        TournamentStructure.deep(),
      ]) {
        expect(s.levels.first.ante, 0);
        expect(s.levels[2].ante, greaterThan(0)); // antes from level 3
        // Blinds are non-decreasing up the ladder.
        for (var i = 1; i < s.levels.length; i++) {
          expect(s.levels[i].bigBlind, greaterThanOrEqualTo(s.levels[i - 1].bigBlind));
        }
      }
    });

    test('turbo has shorter levels and a smaller starting stack than deep', () {
      final turbo = TournamentStructure.turbo(clockMode: LevelClockMode.hands);
      final deep = TournamentStructure.deep(clockMode: LevelClockMode.hands);
      expect(turbo.durationOf(0), lessThan(deep.durationOf(0)));
      expect(turbo.startingStack, lessThan(deep.startingStack));
    });

    test('levelAt caps the blinds past the last defined level', () {
      final s = TournamentStructure.standard();
      final last = s.levels.last;
      final beyond = s.levelAt(s.levels.length + 5);
      expect(beyond.bigBlind, last.bigBlind); // capped
      expect(beyond.level, greaterThan(last.level)); // number keeps climbing
    });

    test('durationOf follows the clock mode', () {
      final byHands = TournamentStructure.standard(clockMode: LevelClockMode.hands);
      final byMinutes =
          TournamentStructure.standard(clockMode: LevelClockMode.minutes);
      expect(byHands.durationOf(0), byHands.levels.first.durationHands);
      expect(byMinutes.durationOf(0), byMinutes.levels.first.durationMinutes);
    });

    test('presetByName resolves the built-ins', () {
      expect(TournamentStructure.presetByName('turbo')?.name, 'Turbo');
      expect(TournamentStructure.presetByName('deep')?.name, 'Deep');
      expect(TournamentStructure.presetByName('nope'), isNull);
    });
  });
}
