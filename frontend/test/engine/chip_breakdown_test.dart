import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/chip_breakdown.dart';
import 'package:monte/features/tournament/domain/chip_set.dart';

void main() {
  final wsop = ChipSet.wsop().denominations;

  ChipBreakdown of(
    int amount, {
    List<int>? denoms,
    int min = 1,
    int maxColumns = 4,
  }) => ChipBreakdown.of(
    amount,
    denominations: denoms ?? wsop,
    minDenomination: min,
    maxColumns: maxColumns,
  );

  group('decomposition', () {
    test('spreads across denominations rather than making minimal change', () {
      // Greedy from the top makes 60,000 out of 2x25,000 + 2x5,000, and no real
      // stack looks like that — chips arrive from blinds, antes and dragged
      // pots, not from a cashier. The spread is 1x25,000, 6x5,000, 4x1,000 and
      // change: one of the biggest, a working pile of the next, more as they
      // get smaller.
      final b = of(60000, min: 100);
      expect(b.columns.first.denomination, 25000);
      expect(b.columns.first.count, 1);
      expect(b.columns.length, 4);
      expect(b.value, 60000, reason: 'a spread still adds up exactly');

      // Counts grow as the chips get smaller — that shape is the whole point.
      expect(b.columns[1].count, greaterThan(b.columns.first.count));
    });

    test('keeps the biggest denomination the player holds', () {
      // Colour is what says who is deep: only a monster stack has a plaque in
      // it at all. Spreading must not spend the top chip away.
      final b = of(1200000, min: 100);
      expect(b.columns.first.denomination, 1000000);
      expect(b.value, 1200000);
    });

    test('reaches four denominations for realistic stacks', () {
      for (final amount in [239400, 735300, 2869600, 60000]) {
        expect(of(amount, min: 100).columns.length, 4,
            reason: '$amount collapsed onto too few colours');
      }
    });

    test('the drawn chips always add up to at least the real amount', () {
      for (final amount in [1, 26, 137, 999, 4321, 60000, 1234567]) {
        expect(
          of(amount).value,
          greaterThanOrEqualTo(amount),
          reason: 'amount $amount drew less than it holds',
        );
      }
    });

    test('never draws a chip smaller than the one in play', () {
      // At a 100/100 level there are no 25 chips on the table.
      final b = of(60350, min: 100);
      for (final c in b.columns) {
        expect(c.denomination, greaterThanOrEqualTo(100));
      }
    });

    test('an amount below the smallest chip still draws one chip', () {
      // A short stack must never render as an empty space.
      final b = of(30, min: 100);
      expect(b.isEmpty, isFalse);
      expect(b.chipCount, 1);
    });

    test('zero and negative amounts draw nothing', () {
      expect(of(0).isEmpty, isTrue);
      expect(of(-500).isEmpty, isTrue);
    });

    test('an empty denomination list draws nothing', () {
      expect(of(5000, denoms: const []).isEmpty, isTrue);
    });
  });

  group('column limit keeps the graphic readable', () {
    test('never exceeds maxColumns', () {
      // An amount with change in every denomination.
      final b = of(1126525, maxColumns: 3);
      expect(b.columns.length, lessThanOrEqualTo(3));
    });

    test('the last column kept absorbs the remainder', () {
      final b = of(1126525, maxColumns: 2);
      expect(b.columns.length, 2);
      // Still covers the full amount despite dropping denominations.
      expect(b.value, greaterThanOrEqualTo(1126525));
    });

    test('columns are ordered largest denomination first', () {
      final b = of(1126525);
      for (var i = 1; i < b.columns.length; i++) {
        expect(
          b.columns[i].denomination,
          lessThan(b.columns[i - 1].denomination),
        );
      }
    });
  });

  group('chipCount', () {
    test('counts physical chips, not value', () {
      final b = of(75000, min: 100);
      expect(b.chipCount, b.columns.fold<int>(0, (a, c) => a + c.count));
      expect(b.chipCount, lessThan(75000));
    });

    test('an exact multiple of one chip really is that one chip', () {
      // The degenerate case the spread cannot fix: 500,000 is a single plaque
      // and 5,000 is a single chip, so a round number draws the chip leader and
      // the short stack the same height. Size is carried by *colour* (only the
      // leader has a plaque at all) and by the number printed on the seat;
      // height was never a reliable signal and pretending otherwise is what
      // made the graphic disagree with its own legend.
      expect(of(500000).chipCount, of(5000).chipCount);
      expect(of(500000).columns.first.denomination,
          greaterThan(of(5000).columns.first.denomination));
    });
  });

  group('ChipColumn', () {
    test('value is denomination x count', () {
      const c = ChipColumn(denomination: 5000, count: 7);
      expect(c.value, 35000);
    });
  });
}
