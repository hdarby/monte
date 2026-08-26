import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/allin_equity.dart';
import 'package:monte/core/domain/engine/card.dart';

List<Card> _hand(String a, String b) => [Card.fromCode(a), Card.fromCode(b)];

void main() {
  group('AllInEquity', () {
    test('AA vs KK preflop is close to the known ~82/18 split', () {
      final result = AllInEquity.compute(
        [_hand('Ah', 'As'), _hand('Kh', 'Ks')],
        const [],
        preflopSamples: 4000,
        random: Random(7),
      );
      expect(result[0], closeTo(0.82, 0.03));
      expect(result[1], closeTo(0.18, 0.03));
      expect(result[0] + result[1], closeTo(1.0, 1e-9));
    });

    test('a fully known river board gives an exact, deterministic result', () {
      // Board: Ah Kh Qh Jh 2c — hero has Th for a royal flush, villain has
      // As Ks for two pair. No cards left to deal, so this must be exact.
      final result = AllInEquity.compute(
        [_hand('Th', '3c'), _hand('As', 'Ks')],
        [
          Card.fromCode('Ah'),
          Card.fromCode('Kh'),
          Card.fromCode('Qh'),
          Card.fromCode('Jh'),
          Card.fromCode('2c'),
        ],
      );
      expect(result[0], 1.0);
      expect(result[1], 0.0);
    });

    test('an exact river chop splits equity evenly between the tied hands',
        () {
      // Both hands play the same board (a straight on board neither can
      // beat), and neither hole card improves it — a guaranteed chop.
      final result = AllInEquity.compute(
        [_hand('2c', '3c'), _hand('2d', '3d')],
        [
          Card.fromCode('9h'),
          Card.fromCode('Th'),
          Card.fromCode('Jh'),
          Card.fromCode('Qh'),
          Card.fromCode('Kh'),
        ],
      );
      expect(result[0], closeTo(0.5, 1e-9));
      expect(result[1], closeTo(0.5, 1e-9));
    });

    test('dead cards are removed from the deck exactly once', () {
      // A card that is part of a hole card must never also appear as a dealt
      // board card — this exercises the flop-enumeration path (need == 2).
      final result = AllInEquity.compute(
        [_hand('Ah', 'As'), _hand('Kh', 'Ks')],
        [Card.fromCode('2c'), Card.fromCode('7d'), Card.fromCode('9s')],
      );
      expect(result[0] + result[1], closeTo(1.0, 1e-9));
      expect(result[0], greaterThan(result[1]));
    });

    test('throws with fewer than two hands', () {
      expect(
        () => AllInEquity.compute([_hand('Ah', 'As')], const []),
        throwsArgumentError,
      );
    });

    test('throws when a hand does not have exactly two cards', () {
      expect(
        () => AllInEquity.compute(
          [
            [Card.fromCode('Ah')],
            _hand('Ks', 'Kd'),
          ],
          const [],
        ),
        throwsArgumentError,
      );
    });
  });
}
