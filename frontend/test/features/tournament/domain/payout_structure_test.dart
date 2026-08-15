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

  group('a Main Event pays like the real thing', () {
    // The published 2024 WSOP Main Event: ~10,000 runners at a 10,000 buy-in,
    // 1st capped at 10,000,000, min cash 15,000, ~15% of the field paid.
    const entrants = 10000;
    const buyIn = 10000;
    const pool = entrants * buyIn;
    final p = PayoutStructure.forFieldSize(entrants);
    final payouts = p.payouts(pool);

    test('pays about 15% of the field', () {
      expect(p.paidPlaces, 1500);
      expect(p.paidPlaces / entrants, closeTo(0.15, 0.005));
    });

    test('caps first place at 10M', () {
      expect(payouts.first, 10000000);
    });

    test('the min cash is exactly 15,000', () {
      expect(payouts.last, 15000);
    });

    test('the middle of the table is not flattened to the min cash', () {
      // The old geometric curve collapsed to the min cash by ~30th place, so a
      // deep run was worth nothing until the final table. Every one of these
      // must be a real, distinct step up.
      expect(payouts[8], greaterThan(900000)); // 9th: real table ~1.0M
      expect(payouts[99], greaterThan(80000)); // 100th: real table ~70k
      expect(payouts[999], greaterThan(17000)); // 1000th: real table ~20k
      expect(payouts[29], greaterThan(2 * payouts.last),
          reason: '30th place used to be worth the min cash');
    });

    test('still sums exactly to the pool', () {
      expect(payouts.reduce((a, b) => a + b), pool);
    });
  });

  group('the first-place cap only bites on a huge field', () {
    test('a small field still pays the winner a big share', () {
      // A cap set in buy-ins is thousands of buy-ins deep, so it cannot touch a
      // 9-handed sit-and-go — the winner should still take over half.
      final p = PayoutStructure.forFieldSize(9);
      expect(p.fractions.first, greaterThan(0.45));
    });

    test('every field size keeps 1st ahead of 2nd', () {
      for (final n in [3, 6, 9, 27, 100, 1000, 5000, 10000, 20000]) {
        final f = PayoutStructure.forFieldSize(n).fractions;
        if (f.length < 2) continue;
        expect(f[0], greaterThan(f[1]), reason: 'field of $n inverted the top');
      }
    });

    test('the min cash is 1.5 buy-ins whatever the field', () {
      for (final n in [27, 100, 1000, 10000]) {
        final payouts = PayoutStructure.forFieldSize(n).payouts(n * 200);
        expect(payouts.last, closeTo(300, 1),
            reason: 'field of $n missed the 1.5 buy-in min cash');
      }
    });
  });
}
