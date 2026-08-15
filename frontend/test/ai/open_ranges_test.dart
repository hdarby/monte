import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/open_ranges.dart';

double _m({
  required int behind,
  int tableSize = 9,
  bool sb = false,
  double dead = 1.5,
  double pos = 0,
}) =>
    OpenRanges.openMultiplier(
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
      expect(sb / btn, closeTo(0.89, 0.06),
          reason: 'charts put the small blind near 40% against the button 45%');
    });

    test('the late seats open several times wider than the early ones', () {
      expect(_m(behind: 2) / _m(behind: 8), greaterThan(2.5),
          reason: 'button vs under the gun should be a real spread');
      expect(_m(behind: 2) / _m(behind: 8), lessThan(5.0),
          reason: 'but not a caricature');
    });

    test('the small blind is a stealing seat, not the tightest one', () {
      // The bug in one assertion: the small blind acts first postflop, which is
      // why it was ranked earliest, but preflop only the big blind is left.
      expect(_m(behind: 1, sb: true), greaterThan(_m(behind: 8)));
      expect(_m(behind: 1, sb: true), greaterThan(1.0));
    });

    test('but it trails the button, being out of position afterwards', () {
      expect(_m(behind: 1, sb: true), lessThan(_m(behind: 2)));
    });

    test('averages 1.0 across the table, so calibration survives', () {
      for (final n in [6, 9, 10]) {
        var sum = 0.0;
        for (var b = 1; b <= n - 1; b++) {
          sum += _m(behind: b, tableSize: n);
        }
        expect(sum / (n - 1), closeTo(1.0, 0.02),
            reason: '$n-handed: this redistributes aggression, not adds it');
      }
    });

    test('Positional_Warfare sharpens the tilt without shifting the mean', () {
      expect(_m(behind: 2, pos: 1.0), greaterThan(_m(behind: 2)));
      expect(_m(behind: 8, pos: 1.0), lessThan(_m(behind: 8)));
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
      final ratio = _m(behind: 2, dead: 2.5) / _m(behind: 2, dead: 1.5);
      expect(ratio, inInclusiveRange(1.1, 1.4),
          reason: 'antes widen ranges; they do not make everyone a maniac');
      // A pathological ante cannot open the range without limit.
      expect(_m(behind: 2, dead: 40), lessThan(_m(behind: 2, dead: 1.5) * 2));
    });

    test('below the no-ante baseline nothing changes', () {
      expect(_m(behind: 3, dead: 1.0), _m(behind: 3, dead: 1.5));
    });
  });

  group('degenerate tables', () {
    test('heads-up and empty cases are a no-op rather than a crash', () {
      expect(_m(behind: 0, tableSize: 9), 1.0);
      expect(_m(behind: 1, tableSize: 1), 1.0);
    });
  });
}
