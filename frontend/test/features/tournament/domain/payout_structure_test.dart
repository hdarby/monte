import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/tournament/domain/payout_structure.dart';

void main() {
  group('PayoutStructure.forFieldSize', () {
    test('pays sensible place counts by field size', () {
      expect(PayoutStructure.forFieldSize(2).paidPlaces, 1);
      expect(PayoutStructure.forFieldSize(5).paidPlaces, 2);
      expect(PayoutStructure.forFieldSize(9).paidPlaces, 3);
      expect(PayoutStructure.forFieldSize(100).paidPlaces, 15); // ~15%
    });

    test('fractions sum to 1.0 and decay top-heavy', () {
      for (final n in [2, 6, 9, 27, 100]) {
        final p = PayoutStructure.forFieldSize(n);
        expect(p.fractions.reduce((a, b) => a + b), closeTo(1.0, 1e-9));
        for (var i = 1; i < p.fractions.length; i++) {
          expect(p.fractions[i], lessThan(p.fractions[i - 1]));
        }
      }
    });

    test('payouts are whole chips that sum exactly to the pool', () {
      final p = PayoutStructure.forFieldSize(9);
      const pool = 9000;
      final payouts = p.payouts(pool);
      expect(payouts.reduce((a, b) => a + b), pool); // remainder folded into 1st
      expect(payouts.first, greaterThan(payouts[1]));
      expect(p.payoutForPlace(4, pool), 0); // unpaid place
      expect(p.payoutForPlace(0, pool), 0); // out of range
    });
  });

  group('PrizePool', () {
    test('totals buy-ins plus rebuys', () {
      expect(const PrizePool(buyIn: 100, entrants: 18, rebuys: 4).total, 2200);
    });
  });
}
