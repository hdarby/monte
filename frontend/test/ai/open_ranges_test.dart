import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/open_ranges.dart';

/// The seat's positional adjustment, in fractions of hands (0.03 = 3 points).
double _d({
  required int behind,
  int tableSize = 9,
  bool sb = false,
  double dead = 1.5,
  double pos = 0,
  double awareness = 1.0,
}) =>
    OpenRanges.positionalDelta(
      playersBehind: behind,
      tableSize: tableSize,
      isSmallBlind: sb,
      deadMoneyBb: dead,
      positionAwareness: awareness,
      positionalProficiency: pos,
    );

/// The resulting opening frequency for a 20% baseline.
double _m({
  required int behind,
  int tableSize = 9,
  bool sb = false,
  double dead = 1.5,
  double pos = 0,
}) =>
    OpenRanges.openFrequency(
      base: 0.20,
      playersBehind: behind,
      tableSize: tableSize,
      isSmallBlind: sb,
      deadMoneyBb: dead,
      positionalProficiency: pos,
    );

/// Opening frequency was flat across the table — measured at button 19%, small
/// blind 15%, under the gun 17%, against a real spread of roughly 15% early to
/// 45% on the button — and the big-blind ante changed it by exactly nothing.
/// The result was a 9.3% walk rate.
///
/// Two causes: position was ranked by *postflop* order, which puts the small
/// blind first and so treated the second-to-last seat to act preflop as the
/// earliest one; and no policy looked at the dead money a steal is playing for.
void main() {
  group('position', () {
    test('fewer players left to act means a wider open', () {
      // Monotonic from the button inward. The small blind (1 behind) is the
      // deliberate exception: it has the fewest players left but is out of
      // position for the rest of the hand, so it steps back below the button.
      var previous = double.infinity;
      for (var behind = 2; behind <= 8; behind++) {
        final m = _m(behind: behind);
        expect(m, lessThan(previous),
            reason: 'opening must tighten with more players behind');
        previous = m;
      }
    });

    test('the button is the widest seat, the small blind just behind it', () {
      final btn = _m(behind: 2);
      final sb = _m(behind: 1, sb: true);
      final co = _m(behind: 3);
      expect(btn, greaterThan(sb));
      expect(sb, greaterThan(co),
          reason: 'the small blind still opens wider than the cutoff');
      expect(btn - sb, closeTo(0.02, 0.02),
          reason: 'the small blind sits about a step below the button');
    });

    test('a fully aware player gains ~4.8 points per position', () {
      // Anchored to real 9/10-handed open-raise ranges: ~13% under the gun to
      // ~42% on the button is six positions apart. A straight line, not a
      // compounding curve.
      for (var behind = 8; behind >= 3; behind--) {
        final step = _d(behind: behind - 1) - _d(behind: behind);
        expect(step, closeTo(0.048, 0.005),
            reason: 'step into the seat with ${behind - 1} behind was $step');
      }
    });

    test('under the gun to the button spans about 29 points', () {
      expect(_d(behind: 2) - _d(behind: 8), closeTo(0.29, 0.02),
          reason: '13% to 42% is six positions at ~4.8 points each');
    });

    test('a less aware player plays a much flatter curve', () {
      // The published curve belongs to someone completely position-aware; a
      // recreational player barely notices where they are sitting.
      final aware = _d(behind: 2) - _d(behind: 8);
      final oblivious = _d(behind: 2, awareness: 0.5) -
          _d(behind: 8, awareness: 0.5);
      expect(oblivious, closeTo(aware / 2, 0.02));
      final none =
          _d(behind: 2, awareness: 0) - _d(behind: 8, awareness: 0);
      expect(none, closeTo(0.0, 0.001),
          reason: 'no awareness means the same range from every seat');
    });

    test('the small blind is a stealing seat, not the tightest one', () {
      // The bug in one assertion: the small blind acts first postflop, which is
      // why it was ranked earliest, but preflop only the big blind is left.
      expect(_d(behind: 1, sb: true), greaterThan(_d(behind: 8)));
      expect(_d(behind: 1, sb: true), greaterThan(0.0),
          reason: 'it should open wider than its own baseline, not tighter');
    });

    test('but it trails the button, being out of position afterwards', () {
      expect(_m(behind: 1, sb: true), lessThan(_m(behind: 2)));
    });

    test('averages zero across the table, so calibration survives', () {
      for (final n in [6, 9, 10]) {
        var sum = 0.0;
        for (var b = 1; b <= n - 1; b++) {
          sum += _d(behind: b, tableSize: n, sb: b <= 1);
        }
        expect(sum / (n - 1), closeTo(0.0, 0.001),
            reason: '$n-handed: this redistributes aggression, not adds it');
      }
    });

    test('Positional_Warfare sharpens the tilt without shifting the mean', () {
      expect(_d(behind: 2, pos: 1.0), greaterThan(_d(behind: 2)));
      expect(_d(behind: 8, pos: 1.0), lessThan(_d(behind: 8)));
    });
  });

  group('dead money', () {
    test('a big-blind ante widens the opening range', () {
      // No ante the pot is 1.5 BB; with a 1 BB big-blind ante it is 2.5 BB, so
      // the same raise is risking the same to win far more.
      expect(_m(behind: 2, dead: 2.5), greaterThan(_m(behind: 2, dead: 1.5)));
    });

    test('it lifts every seat, since the dead money is there for all of them', () {
      for (final behind in [1, 2, 5, 8]) {
        expect(_m(behind: behind, dead: 2.5),
            greaterThan(_m(behind: behind, dead: 1.5)),
            reason: 'seat with $behind behind ignored the ante');
      }
    });

    test('the widening is meaningful but bounded', () {
      final added = _d(behind: 2, dead: 2.5) - _d(behind: 2, dead: 1.5);
      expect(added, inInclusiveRange(0.015, 0.05),
          reason: 'antes widen ranges; they do not make everyone a maniac');
      // A pathological ante cannot open the range without limit.
      expect(_d(behind: 2, dead: 40) - _d(behind: 2, dead: 1.5),
          lessThan(0.10));
    });

    test('below the no-ante baseline nothing changes', () {
      expect(_d(behind: 3, dead: 1.0), _d(behind: 3, dead: 1.5));
    });
  });

  group('degenerate tables', () {
    test('heads-up and empty cases are a no-op rather than a crash', () {
      expect(_d(behind: 0, tableSize: 9), 0.0);
      expect(_d(behind: 1, tableSize: 1), 0.0);
    });
  });
}
