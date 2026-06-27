import 'package:poker_client/core/domain/engine/card.dart';

/// Poker hand categories, ordered from weakest to strongest.
enum HandRank {
  highCard('High Card'),
  pair('Pair'),
  twoPair('Two Pair'),
  threeOfAKind('Three of a Kind'),
  straight('Straight'),
  flush('Flush'),
  fullHouse('Full House'),
  fourOfAKind('Four of a Kind'),
  straightFlush('Straight Flush');

  const HandRank(this.label);

  final String label;
}

/// The evaluated strength of a five-card hand.
///
/// Comparison is by [rank] first, then by [tiebreakers] (each a card value,
/// most significant first), which makes [HandValue] a total order suitable for
/// `sort` / `reduce(max)`.
class HandValue implements Comparable<HandValue> {
  const HandValue(this.rank, this.tiebreakers, this.bestFive);

  final HandRank rank;
  final List<int> tiebreakers;

  /// The exact five cards that produced this value (best 5 of the 7).
  final List<Card> bestFive;

  @override
  int compareTo(HandValue other) {
    if (rank.index != other.rank.index) {
      return rank.index - other.rank.index;
    }
    for (var i = 0; i < tiebreakers.length; i++) {
      final diff = tiebreakers[i] - other.tiebreakers[i];
      if (diff != 0) return diff;
    }
    return 0;
  }

  bool operator >(HandValue other) => compareTo(other) > 0;
  bool operator <(HandValue other) => compareTo(other) < 0;

  @override
  String toString() => '${rank.label} $tiebreakers';
}

/// Evaluates the best 5-card poker hand from 5, 6, or 7 cards.
class HandEvaluator {
  /// Returns the strongest [HandValue] obtainable from [cards].
  ///
  /// Accepts 5–7 cards (typically 2 hole + up to 5 community). Throws if fewer
  /// than 5 are supplied.
  static HandValue evaluate(List<Card> cards) {
    if (cards.length < 5) {
      throw ArgumentError('Need at least 5 cards to evaluate, got ${cards.length}');
    }
    if (cards.length == 5) return _score5(cards);

    HandValue? best;
    for (final combo in _combinations(cards, 5)) {
      final value = _score5(combo);
      if (best == null || value > best) best = value;
    }
    return best!;
  }

  /// Scores exactly five cards.
  static HandValue _score5(List<Card> five) {
    final sorted = [...five]..sort((a, b) => b.rank.value - a.rank.value);
    final values = sorted.map((c) => c.rank.value).toList();

    final isFlush = sorted.every((c) => c.suit == sorted.first.suit);

    // Count occurrences of each rank value.
    final counts = <int, int>{};
    for (final v in values) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
    // Distinct values sorted by (count desc, value desc) for tiebreakers.
    final byCount = counts.keys.toList()
      ..sort((a, b) {
        final c = counts[b]! - counts[a]!;
        return c != 0 ? c : b - a;
      });
    final countPattern = byCount.map((v) => counts[v]!).toList();

    final straightHigh = _straightHigh(values.toSet());

    if (isFlush && straightHigh != null) {
      return HandValue(HandRank.straightFlush, [straightHigh], sorted);
    }
    if (countPattern.first == 4) {
      // Quads + kicker.
      return HandValue(HandRank.fourOfAKind, byCount, sorted);
    }
    if (countPattern.length >= 2 && countPattern[0] == 3 && countPattern[1] >= 2) {
      return HandValue(HandRank.fullHouse, byCount, sorted);
    }
    if (isFlush) {
      return HandValue(HandRank.flush, values, sorted);
    }
    if (straightHigh != null) {
      return HandValue(HandRank.straight, [straightHigh], sorted);
    }
    if (countPattern.first == 3) {
      return HandValue(HandRank.threeOfAKind, byCount, sorted);
    }
    if (countPattern.length >= 2 && countPattern[0] == 2 && countPattern[1] == 2) {
      return HandValue(HandRank.twoPair, byCount, sorted);
    }
    if (countPattern.first == 2) {
      return HandValue(HandRank.pair, byCount, sorted);
    }
    return HandValue(HandRank.highCard, values, sorted);
  }

  /// Returns the high card value of a straight contained in [valueSet], or null.
  /// Handles the wheel (A-2-3-4-5), where the ace counts as 1 and the high is 5.
  static int? _straightHigh(Set<int> valueSet) {
    // Ace can be low: add 1 if an ace (14) is present.
    final vals = {...valueSet};
    if (vals.contains(14)) vals.add(1);
    final sorted = vals.toList()..sort((a, b) => b - a);

    var run = 1;
    for (var i = 0; i < sorted.length - 1; i++) {
      if (sorted[i] - 1 == sorted[i + 1]) {
        run++;
        if (run >= 5) return sorted[i - 3];
      } else {
        run = 1;
      }
    }
    return null;
  }

  /// Yields every k-combination of [items].
  static Iterable<List<Card>> _combinations(List<Card> items, int k) sync* {
    final n = items.length;
    final indices = List<int>.generate(k, (i) => i);
    while (true) {
      yield [for (final i in indices) items[i]];
      var i = k - 1;
      while (i >= 0 && indices[i] == n - k + i) {
        i--;
      }
      if (i < 0) return;
      indices[i]++;
      for (var j = i + 1; j < k; j++) {
        indices[j] = indices[j - 1] + 1;
      }
    }
  }
}
