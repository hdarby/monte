import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/hand_range.dart';
import 'package:monte/core/domain/ai/postflop_equity.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_strength.dart';

import '../_helpers.dart';

double _eq(String hole, String board, HandRange range, {int iters = 800}) =>
    PostflopEquity.equity(
      cards(hole),
      cards(board),
      range,
      iterations: iters,
      random: Random(42),
    );

void main() {
  group('HandRange', () {
    test('all excludes dead cards and counts combos', () {
      final dead = {...cards('As Ks'), ...cards('2h 7d 9c')};
      final r = HandRange.all(dead: dead);
      // C(47, 2) live combos once 5 cards are removed.
      expect(r.length, 47 * 46 ~/ 2);
      for (final c in r.combos) {
        expect(dead.contains(c.$1), isFalse);
        expect(dead.contains(c.$2), isFalse);
      }
    });

    test('top(fraction) keeps the strongest hands, ranked', () {
      final r = HandRange.top(0.1);
      // Strongest combo must be a premium (AA/KK); its preflopOf beats a random
      // weak combo.
      final best = r.combos.first;
      expect(
        HandStrength.preflopOf(best.$1, best.$2),
        greaterThan(HandStrength.preflopOf(card('7c'), card('2d'))),
      );
      // ~10% of 1326.
      expect(r.length, closeTo(133, 10));
    });

    test('narrowedBy tightens with raises and streets', () {
      final base = HandRange.top(0.6);
      expect(base.narrowedBy(raiseCount: 1).length, lessThan(base.length));
      expect(
        base.narrowedBy(raiseCount: 2).length,
        lessThan(base.narrowedBy(raiseCount: 1).length),
      );
      expect(
        base.narrowedBy(street: BettingRound.river).length,
        lessThan(base.length),
      );
    });
  });

  group('PostflopEquity', () {
    test('the nuts crush any range', () {
      // Royal flush on board+hole vs everything.
      final eq = _eq('As Ks', 'Qs Js Ts 2h 3d', HandRange.all());
      expect(eq, greaterThan(0.99));
    });

    test('a weak hand vs a strong range has low equity', () {
      // River: hero's 72o only plays the board's two pair (AAKK) — it chops the
      // range and loses to any broadway (JT), so equity sits well below a flip.
      final eq = _eq('7c 2d', 'Ah Ad Kh Ks Qd', HandRange.top(0.2));
      expect(eq, lessThan(0.25));
    });

    test('a flush draw carries real equity over a made bottom pair', () {
      final range = HandRange.top(0.5);
      final drawEq = _eq('Ah Kh', 'Qh 7h 2c', range); // nut flush draw + overs
      final bottomPair = _eq('3s 2s', 'Qh 7h 2d', range); // pair of deuces
      expect(drawEq, greaterThan(0.4));
      expect(drawEq, greaterThan(bottomPair));
    });

    test('top pair top kicker beats second pair vs the same range', () {
      final range = HandRange.top(0.4);
      final tptk = _eq('As Kd', 'Ah 8c 3d', range);
      final second = _eq('Ks Qd', 'Ah Kc 3d', range);
      expect(tptk, greaterThan(second));
    });

    test('is reproducible under a fixed seed', () {
      final a = _eq('Ah Kh', 'Qh 7h 2c', HandRange.top(0.5));
      final b = _eq('Ah Kh', 'Qh 7h 2c', HandRange.top(0.5));
      expect(a, b);
    });

    test('river enumerates exactly (seed-independent)', () {
      final range = HandRange.top(0.3);
      final board = 'Ah Kc 3d 9s 4h';
      final a = PostflopEquity.equity(
        cards('As Kd'),
        cards(board),
        range,
        random: Random(1),
      );
      final b = PostflopEquity.equity(
        cards('As Kd'),
        cards(board),
        range,
        random: Random(999),
      );
      expect(a, b); // no runout to sample -> deterministic
    });
  });
}
