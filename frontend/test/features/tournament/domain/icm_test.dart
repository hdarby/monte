import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/tournament/domain/icm.dart';

void main() {
  group('Icm.equities', () {
    test('two-player heads-up matches the hand-computed values', () {
      // A=75, B=25, payouts 70/30. A = .75*70 + .25*30 = 60; B = 40.
      final eq = Icm.equities([75, 25], [70, 30]);
      expect(eq[0], closeTo(60, 1e-6));
      expect(eq[1], closeTo(40, 1e-6));
    });

    test('equal stacks split equity evenly (symmetry)', () {
      final eq = Icm.equities([100, 100, 100], [50, 30, 20]);
      for (final e in eq) {
        expect(e, closeTo(100 / 3, 1e-6));
      }
    });

    test('equity sums to the prize pool and is monotonic in stack', () {
      final eq = Icm.equities([50, 30, 20], [60, 40]);
      expect(eq.reduce((a, b) => a + b), closeTo(100, 1e-6));
      expect(eq[0], greaterThan(eq[1]));
      expect(eq[1], greaterThan(eq[2]));
    });

    test('a busted (0-chip) player has ~no equity when others hold chips', () {
      final eq = Icm.equities([80, 20, 0], [60, 40]);
      expect(eq[2], closeTo(0, 1e-6));
      expect(eq[0] + eq[1], closeTo(100, 1e-6));
    });

    test('doubling a stack less than doubles equity (ICM concavity)', () {
      final base = Icm.equities([25, 25, 25, 25], [40, 30, 20, 10]);
      final doubled = Icm.equities([50, 25, 25, 0], [40, 30, 20, 10]);
      // Player 0 doubled from 25->50 by busting player 3.
      expect(doubled[0], greaterThan(base[0]));
      expect(doubled[0], lessThan(2 * base[0]));
    });

    test('large fields fall back to a chip-proportional approximation', () {
      final stacks = List<int>.filled(20, 100)..[0] = 200; // 21 total? no, 20
      final total = stacks.fold<int>(0, (a, b) => a + b);
      final eq = Icm.equities(stacks, [500, 300, 200]);
      // Proportional: player 0 has 200/total of the 1000 pool.
      expect(eq[0], closeTo(200 / total * 1000, 1e-6));
    });
  });

  group('Icm.bubbleFactor', () {
    test('is above 1 on the bubble (losing costs more than winning gains)', () {
      // 4 left, 3 paid: classic bubble. A short-ish stack faces real ICM risk.
      final bf = Icm.bubbleFactor([4000, 3000, 2000, 1000], [50, 30, 20], 3);
      expect(bf, greaterThan(1.0));
    });

    test('a big stack protects more than the desperate short stack (ICM)', () {
      // ICM-correct: the short stack has ~no equity to lose (≈0 if it busts on
      // the bubble), so it faces the LEAST pressure and can gamble; the chip
      // leader has the most equity to protect, so the highest bubble factor.
      final stacks = [8000, 3000, 2000, 1000];
      const payouts = [50, 30, 20];
      final leader = Icm.bubbleFactor(stacks, payouts, 0);
      final shorty = Icm.bubbleFactor(stacks, payouts, 3);
      expect(shorty, lessThan(leader));
    });
  });
}
