import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/hand_strength.dart';

import '_helpers.dart';

// All 169 canonical starting hands, each as a representative two-card combo.
// Suited hands share a suit; offsuit/pairs use two suits.
double _s(String twoRanks, {required bool suited}) {
  final hi = twoRanks[0], lo = twoRanks[1];
  return HandStrength.preflopOf(
    card('${hi}s'),
    card('$lo${suited ? 's' : 'h'}'),
  );
}

Iterable<double> _allStrengths() sync* {
  const ranks = '23456789TJQKA';
  for (var i = 0; i < ranks.length; i++) {
    for (var j = i; j < ranks.length; j++) {
      final hi = ranks[j], lo = ranks[i];
      if (i == j) {
        yield _s('$hi$lo', suited: false); // pair
      } else {
        yield _s('$hi$lo', suited: true);
        yield _s('$hi$lo', suited: false);
      }
    }
  }
}

void main() {
  group('HandStrength.preflopOf', () {
    test('is defined and in-range for every starting hand', () {
      final all = _allStrengths().toList();
      expect(all, hasLength(169));
      for (final s in all) {
        expect(s, inInclusiveRange(0.0, 1.0));
      }
    });

    test('pairs are strictly monotone 22 < .. < AA, AA is the top hand', () {
      const ranks = '23456789TJQKA';
      var prev = -1.0;
      for (final r in ranks.split('')) {
        final s = _s('$r$r', suited: false);
        expect(s, greaterThan(prev), reason: 'pair $r$r should exceed lower pairs');
        prev = s;
      }
      final aa = _s('AA', suited: false);
      expect(aa, equals(_allStrengths().reduce((a, b) => a > b ? a : b)));
    });

    test('suited beats its offsuit twin for every rank pair', () {
      const ranks = '23456789TJQKA';
      for (var i = 0; i < ranks.length; i++) {
        for (var j = i + 1; j < ranks.length; j++) {
          final combo = '${ranks[j]}${ranks[i]}';
          expect(
            _s(combo, suited: true),
            greaterThan(_s(combo, suited: false)),
            reason: '${combo}s should beat ${combo}o',
          );
        }
      }
    });

    test('order is invariant to card argument order', () {
      expect(
        HandStrength.preflopOf(card('Ah'), card('Ks')),
        HandStrength.preflopOf(card('Ks'), card('Ah')),
      );
    });

    test('fixes the ordering bugs the tiered grid had', () {
      // KJs > KTs and KJs > QJo (both inverted by the naive gap-based grid).
      expect(_s('KJ', suited: true), greaterThan(_s('KT', suited: true)));
      expect(_s('KJ', suited: true), greaterThan(_s('QJ', suited: false)));
      // Standard premium ordering.
      expect(_s('AK', suited: true), greaterThan(_s('AQ', suited: true)));
      expect(_s('AQ', suited: true), greaterThan(_s('AK', suited: false)));
      expect(_s('AK', suited: false), greaterThan(_s('AQ', suited: false)));
    });

    test('preserves the legacy output distribution (drop-in scale)', () {
      // Histogram-matched onto the old smooth formula, so the number of combos
      // above the heuristic bot's preflop entry (0.50) — i.e. the VPIP the
      // default bot realises — must match what the old formula admitted,
      // weighted by combo counts (pair 6, suited 4, offsuit 12) = 1326 total.
      double legacy(int a, int b, bool suited) {
        if (a == b) return 0.50 + 0.45 * ((a - 2) / 12);
        final hi = a > b ? a : b, lo = a > b ? b : a;
        var s = (hi + lo) / 28.0 * 0.6;
        if (suited) s += 0.08;
        if (hi - lo == 1) s += 0.05;
        if (hi == 14) s += 0.05;
        return s.clamp(0.0, 1.0);
      }

      const ranks = '23456789TJQKA';
      var admittedNew = 0, admittedOld = 0;
      for (var i = 0; i < ranks.length; i++) {
        for (var j = i; j < ranks.length; j++) {
          final combo = '${ranks[j]}${ranks[i]}';
          final a = i + 2, b = j + 2;
          void tally(bool suited, int w) {
            if (_s(combo, suited: suited) >= 0.50) admittedNew += w;
            if (legacy(a, b, suited) >= 0.50) admittedOld += w;
          }

          if (i == j) {
            tally(false, 6);
          } else {
            tally(true, 4);
            tally(false, 12);
          }
        }
      }
      // Within one hand-class of quantisation of the legacy count.
      expect(admittedNew, closeTo(admittedOld, 24));
    });
  });
}
