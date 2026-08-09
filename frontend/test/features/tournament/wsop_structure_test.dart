import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

/// The Main Event structure mirrors the real event. These are facts about the
/// live tournament, not preferences, so they get pinned down.
void main() {
  final main = TournamentStructure.wsopMainEvent();

  group('WSOP Main Event', () {
    test('starts at 100/200 — there is no 100/100 level', () {
      final first = main.levels.first;
      expect(first.smallBlind, 100);
      expect(first.bigBlind, 200);
      expect(first.ante, 0);
    });

    test('has a 60,000 starting stack (300 big blinds)', () {
      expect(main.startingStack, 60000);
      expect(main.startingStack / main.levels.first.bigBlind, 300);
    });

    test('runs 2-hour levels, which is 50 hands of live play', () {
      // ~25 hands an hour live. This sets how many hands a Day 1 contains, so
      // it drives the whole shape of early-tournament play.
      for (final l in main.levels) {
        expect(l.durationMinutes, 120);
        expect(l.durationHands, 50);
      }
    });

    test('a Day 1 of five levels is about 250 hands', () {
      final dayOne = main.levels
          .take(5)
          .fold(0, (sum, l) => sum + (l.durationHands ?? 0));
      expect(dayOne, 250);
    });

    test('introduces antes at level 4 and keeps them from then on', () {
      expect(main.levels[2].ante, 0);
      expect(main.levels[3].ante, greaterThan(0));
      for (final l in main.levels.skip(3)) {
        expect(l.ante, greaterThan(0), reason: 'level ${l.level} lost its ante');
      }
    });

    test('blinds never decrease and the big blind never trails the small', () {
      for (var i = 0; i < main.levels.length; i++) {
        final l = main.levels[i];
        expect(l.bigBlind, greaterThanOrEqualTo(l.smallBlind));
        if (i > 0) {
          expect(l.bigBlind, greaterThanOrEqualTo(main.levels[i - 1].bigBlind));
        }
      }
    });

    test('level numbers are 1-indexed and contiguous', () {
      for (var i = 0; i < main.levels.length; i++) {
        expect(main.levels[i].level, i + 1);
      }
    });

    test('durationOf reports hands or minutes per the clock mode', () {
      final hands = TournamentStructure.wsopMainEvent(
        clockMode: LevelClockMode.hands,
      );
      final minutes = TournamentStructure.wsopMainEvent(
        clockMode: LevelClockMode.minutes,
      );
      expect(hands.durationOf(0), 50);
      expect(minutes.durationOf(0), 120);
    });
  });
}
