import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';

import '_helpers.dart';

void main() {
  group('HandEvaluator category detection', () {
    test('straight flush', () {
      final v = HandEvaluator.evaluate(cards('9s 8s 7s 6s 5s'));
      expect(v.rank, HandRank.straightFlush);
      expect(v.tiebreakers.first, 9);
    });

    test('wheel straight flush (A-5)', () {
      final v = HandEvaluator.evaluate(cards('As 2s 3s 4s 5s'));
      expect(v.rank, HandRank.straightFlush);
      expect(v.tiebreakers.first, 5, reason: 'ace plays low, five is high');
    });

    test('four of a kind', () {
      final v = HandEvaluator.evaluate(cards('Qs Qd Qh Qc 3s'));
      expect(v.rank, HandRank.fourOfAKind);
    });

    test('full house', () {
      final v = HandEvaluator.evaluate(cards('Ks Kd Kh 7c 7s'));
      expect(v.rank, HandRank.fullHouse);
    });

    test('flush', () {
      final v = HandEvaluator.evaluate(cards('Ah Jh 9h 6h 2h'));
      expect(v.rank, HandRank.flush);
    });

    test('wheel straight', () {
      final v = HandEvaluator.evaluate(cards('Ad 2c 3h 4s 5d'));
      expect(v.rank, HandRank.straight);
      expect(v.tiebreakers.first, 5);
    });

    test('two pair', () {
      final v = HandEvaluator.evaluate(cards('Ad Ah 9c 9s 4d'));
      expect(v.rank, HandRank.twoPair);
    });

    test('high card', () {
      final v = HandEvaluator.evaluate(cards('Ad Jh 9c 6s 4d'));
      expect(v.rank, HandRank.highCard);
    });
  });

  group('Best-5-of-7 selection', () {
    test('picks the flush hidden in 7 cards', () {
      final v = HandEvaluator.evaluate(cards('Ah Kh 2h 7h 9h 3s 4d'));
      expect(v.rank, HandRank.flush);
    });

    test('picks quads over a tempting full house', () {
      final v = HandEvaluator.evaluate(cards('8s 8d 8h 8c Kd Kh 2s'));
      expect(v.rank, HandRank.fourOfAKind);
    });
  });

  group('Ranking and tiebreakers', () {
    test('category ordering is strict', () {
      final sf = HandEvaluator.evaluate(cards('9s 8s 7s 6s 5s'));
      final quads = HandEvaluator.evaluate(cards('Qs Qd Qh Qc 3s'));
      final boat = HandEvaluator.evaluate(cards('Ks Kd Kh 7c 7s'));
      final flush = HandEvaluator.evaluate(cards('Ah Jh 9h 6h 2h'));
      expect(sf > quads, isTrue);
      expect(quads > boat, isTrue);
      expect(boat > flush, isTrue);
    });

    test('higher kicker wins with equal pair', () {
      final aceKicker = HandEvaluator.evaluate(cards('Ts Td Ah 5c 3s'));
      final kingKicker = HandEvaluator.evaluate(cards('Th Tc Ks 5d 3h'));
      expect(aceKicker > kingKicker, isTrue);
    });

    test('identical hands tie', () {
      final a = HandEvaluator.evaluate(cards('Ts Td 9h 5c 3s'));
      final b = HandEvaluator.evaluate(cards('Th Tc 9d 5h 3c'));
      expect(a.compareTo(b), 0);
    });
  });
}
