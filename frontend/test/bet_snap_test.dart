import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/bet_snap.dart';

void main() {
  group('snapBet', () {
    test('rounds to human denominations at 5/10', () {
      expect(snapBet(37, smallBlind: 5, bigBlind: 10), 35);
      expect(snapBet(43, smallBlind: 5, bigBlind: 10), 45);
      expect(snapBet(150, smallBlind: 5, bigBlind: 10), 150);
      expect(snapBet(275, smallBlind: 5, bigBlind: 10), 280);
      expect(snapBet(1000, smallBlind: 5, bigBlind: 10), 1000);
    });

    test('scales with the stake', () {
      // 25/50: finest denomination is the small blind (25).
      expect(snapBet(137, smallBlind: 25, bigBlind: 50) % 25, 0);
      expect(snapBet(137, smallBlind: 25, bigBlind: 50), 125);
      // 100/200: everything snaps to hundreds+.
      final s = snapBet(1337, smallBlind: 100, bigBlind: 200);
      expect(s % 100, 0);
      expect(s, closeTo(1400, 200));
    });

    test('leaves min-raise-sized amounts (<= big blind) untouched', () {
      expect(snapBet(10, smallBlind: 5, bigBlind: 10), 10);
      expect(snapBet(7, smallBlind: 5, bigBlind: 10), 7);
    });

    test('never returns zero for a positive bet', () {
      for (var a = 1; a <= 500; a++) {
        expect(snapBet(a, smallBlind: 5, bigBlind: 10), greaterThan(0));
      }
    });

    test('is idempotent (snapping a snapped amount is a no-op)', () {
      for (final a in [37, 43, 150, 275, 512, 1000, 3333]) {
        final once = snapBet(a, smallBlind: 5, bigBlind: 10);
        final twice = snapBet(once, smallBlind: 5, bigBlind: 10);
        expect(twice, once, reason: 'a=$a once=$once');
      }
    });

    test('degrades gracefully with a zero small blind', () {
      expect(snapBet(37, smallBlind: 0, bigBlind: 10), 40); // unit falls back to bb
    });
  });
}
