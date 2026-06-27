import 'dart:math';

import 'package:poker_client/core/domain/engine/card.dart';

/// A shuffleable 52-card deck that deals from the top.
class Deck {
  Deck({Random? random}) : _random = random ?? Random.secure() {
    reset();
  }

  final Random _random;
  final List<Card> _cards = [];

  /// Cards remaining to be dealt.
  int get remaining => _cards.length;

  /// Rebuilds a full, ordered 52-card deck.
  void reset() {
    _cards
      ..clear()
      ..addAll([
        for (final suit in Suit.values)
          for (final rank in Rank.values) Card(rank, suit),
      ]);
  }

  /// Fisher–Yates shuffle.
  void shuffle() {
    for (var i = _cards.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final tmp = _cards[i];
      _cards[i] = _cards[j];
      _cards[j] = tmp;
    }
  }

  /// Deals a single card from the top of the deck.
  Card deal() {
    if (_cards.isEmpty) {
      throw StateError('Cannot deal from an empty deck');
    }
    return _cards.removeLast();
  }

  /// Deals [count] cards.
  List<Card> dealMany(int count) => [for (var i = 0; i < count; i++) deal()];

  /// Burns a card (discards it without using it), as in real dealing.
  void burn() => deal();
}
