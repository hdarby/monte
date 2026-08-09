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
    test('is greedy from the largest denomination down', () {
      // 60,000 is 2x25,000 + 2x5,000 (not sixty 1,000s).
      final b = of(60000);
      expect(b.columns.first.denomination, 25000);
      expect(b.columns.first.count, 2);
      expect(b.value, 60000);
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

    test('folds the unrepresented remainder into the smallest kept column', () {
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
      final b = of(75000); // 3 x 25,000
      expect(b.chipCount, 3);
    });

    test('does NOT track stack size — which is why the view scales instead', () {
      // Greedy denominations invert the picture: 500,000 is a single plaque
      // while 5,000 is a single chip, so literal chip counts would draw the
      // chip leader and the short stack identically. ChipStackView therefore
      // scales height against the table's biggest stack rather than using this.
      expect(of(500000).chipCount, of(5000).chipCount);
    });
  });

  group('ChipColumn', () {
    test('value is denomination x count', () {
      const c = ChipColumn(denomination: 5000, count: 7);
      expect(c.value, 35000);
    });
  });
}
