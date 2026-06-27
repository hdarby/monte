import 'package:poker_client/core/domain/engine/card.dart';

/// Parses a compact code like `As`, `Td`, `2c` into a [Card] for tests.
Card card(String code) {
  final rank = Rank.values.firstWhere((r) => r.label == code[0].toUpperCase());
  final suit = Suit.values.firstWhere((s) => s.letter == code[1].toLowerCase());
  return Card(rank, suit);
}

List<Card> cards(String codes) =>
    codes.split(' ').where((s) => s.isNotEmpty).map(card).toList();
