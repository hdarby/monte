import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/card.dart';

void main() {
  group('Card.fromCode', () {
    test('round-trips every card in the deck', () {
      for (final rank in Rank.values) {
        for (final suit in Suit.values) {
          final c = Card(rank, suit);
          expect(Card.fromCode(c.code), c);
        }
      }
    });

    test('parses mixed-case codes', () {
      expect(Card.fromCode('as'), const Card(Rank.ace, Suit.spades));
      expect(Card.fromCode('TD'), const Card(Rank.ten, Suit.diamonds));
      expect(Card.fromCode('2C'), const Card(Rank.two, Suit.clubs));
    });

    test('throws on malformed codes', () {
      expect(() => Card.fromCode(''), throwsFormatException);
      expect(() => Card.fromCode('A'), throwsFormatException);
      expect(() => Card.fromCode('Zx'), throwsFormatException);
      expect(() => Card.fromCode('Ak'), throwsFormatException); // no 'k' suit
    });
  });
}
