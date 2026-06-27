import 'package:meta/meta.dart';

/// The four suits of a standard 52-card deck.
///
/// Pure engine type — no Flutter/UI imports. Display colour lives in the
/// presentation layer (see `core/presentation/suit_color.dart`).
enum Suit {
  spades('♠', '♠'),
  hearts('♥', '♥'),
  diamonds('♦', '♦'),
  clubs('♣', '♣');

  const Suit(this.symbol, this.code);

  /// Unicode glyph used in the UI, e.g. '♠'.
  final String symbol;

  /// Single-character code used in card codes / serialization, e.g. 's'.
  final String code;

  /// Lowercase letter form used in compact card codes such as `As`.
  String get letter => name[0];
}

/// Card ranks ordered from low (two) to high (ace).
///
/// [value] is the natural high-ace ordering used everywhere except wheel
/// straight detection, where the ace can also act as a 1.
enum Rank {
  two(2, '2'),
  three(3, '3'),
  four(4, '4'),
  five(5, '5'),
  six(6, '6'),
  seven(7, '7'),
  eight(8, '8'),
  nine(9, '9'),
  ten(10, 'T'),
  jack(11, 'J'),
  queen(12, 'Q'),
  king(13, 'K'),
  ace(14, 'A');

  const Rank(this.value, this.label);

  /// Numeric strength, 2..14 (ace high).
  final int value;

  /// Short display label, e.g. 'T', 'J', 'A'.
  final String label;
}

/// An immutable playing card.
@immutable
class Card {
  const Card(this.rank, this.suit);

  final Rank rank;
  final Suit suit;

  /// Compact code such as `As`, `Td`, `2c`.
  String get code => '${rank.label}${suit.letter}';

  @override
  bool operator ==(Object other) =>
      other is Card && other.rank == rank && other.suit == suit;

  @override
  int get hashCode => Object.hash(rank, suit);

  @override
  String toString() => code;
}
