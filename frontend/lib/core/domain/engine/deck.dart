import 'dart:math';

import 'package:monte/core/domain/engine/card.dart';

/// A shuffleable 52-card deck that deals from the top.
class Deck {
  Deck({Random? random}) : _random = random ?? Random.secure() {
    reset();
  }

  /// Creates a deck that always deals [dealOrder] from the top, front-to-back.
  /// The order is *preset*: it survives [reset]/[shuffle] (both become no-ops),
  /// so a game started on this deck deals a known, reproducible board. Used for
  /// deterministic scenarios and tests.
  Deck.stacked(List<Card> dealOrder, {Random? random})
    : _random = random ?? Random() {
    _cards.addAll(dealOrder.reversed);
    _preset = List.of(_cards);
  }

  final Random _random;
  final List<Card> _cards = [];

  /// When non-null, the fixed deal order this deck restores on [reset] and keeps
  /// through [shuffle]. Set only for [Deck.stacked] decks.
  List<Card>? _preset;

  /// Cards remaining to be dealt.
  int get remaining => _cards.length;

  /// A copy that preserves the exact remaining cards and their deal order, so a
  /// cloned game deals identically. Randomness is independent — no reshuffle
  /// occurs during forward simulation, so this never diverges.
  Deck copy() {
    final d = Deck.stacked(const []);
    d._cards.addAll(_cards);
    d._preset = _preset == null ? null : List.of(_preset!);
    return d;
  }

  /// Replaces the remaining cards with [dealOrder] (dealt front-to-back). Used
  /// by the determinizer to inject a sampled future onto a cloned game.
  void loadRemaining(List<Card> dealOrder) {
    _cards
      ..clear()
      ..addAll(dealOrder.reversed);
  }

  /// Rebuilds a full, ordered 52-card deck — or restores the preset deal order
  /// for a [Deck.stacked] deck.
  void reset() {
    if (_preset != null) {
      _cards
        ..clear()
        ..addAll(_preset!);
      return;
    }
    _cards
      ..clear()
      ..addAll([
        for (final suit in Suit.values)
          for (final rank in Rank.values) Card(rank, suit),
      ]);
  }

  /// Fisher–Yates shuffle. A no-op for a preset [Deck.stacked] deck.
  void shuffle() {
    if (_preset != null) return;
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
