import 'dart:math';

import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';

/// Exact head-to-head equity for hands that are **both known** — the situation
/// a completed replay is in (nobody's cards are hidden after the fact), unlike
/// `PostflopEquity`, which estimates against a range because the live AI can't
/// see the villain's hole cards. No range, no approximation needed: just deal
/// out what's left of the deck and count wins.
///
/// Ties split evenly between every hand sharing the best value at that runout,
/// matching how a real side pot splits.
class AllInEquity {
  const AllInEquity._();

  /// Equity for each of [hands] given [boardSoFar] (0–5 known board cards),
  /// enumerating every possible completion of the board. Preflop (0 known
  /// board cards) is capped at Monte-Carlo [preflopSamples] runouts — full
  /// enumeration there is 1712304 combinations for two hands and grows
  /// combinatorially with the field, not worth it for a number that only
  /// narrates a hand.
  ///
  /// Returns one probability per entry in [hands], summing to 1 (a tie is
  /// split, not double-counted). Throws if [hands] has fewer than 2 entries or
  /// any hand doesn't have exactly 2 cards.
  static List<double> compute(
    List<List<Card>> hands,
    List<Card> boardSoFar, {
    int preflopSamples = 2000,
    Random? random,
  }) {
    if (hands.length < 2) {
      throw ArgumentError('Need at least two hands to compare equity.');
    }
    for (final h in hands) {
      if (h.length != 2) {
        throw ArgumentError('Each hand must have exactly two cards.');
      }
    }

    final dead = {...boardSoFar, for (final h in hands) ...h};
    final remaining = [
      for (final suit in Suit.values)
        for (final rank in Rank.values)
          if (!dead.contains(Card(rank, suit))) Card(rank, suit),
    ];

    final need = 5 - boardSoFar.length;
    final wins = List<double>.filled(hands.length, 0.0);
    var trials = 0;

    void score(List<Card> board) {
      final values = [
        for (final h in hands) HandEvaluator.evaluate([...h, ...board]),
      ];
      var best = values[0];
      for (final v in values.skip(1)) {
        if (v > best) best = v;
      }
      final winners = [
        for (var i = 0; i < values.length; i++)
          if (values[i].compareTo(best) == 0) i,
      ];
      for (final i in winners) {
        wins[i] += 1.0 / winners.length;
      }
      trials++;
    }

    if (need == 0) {
      score(boardSoFar);
    } else if (need <= 2) {
      // Flop/turn: enumerate exactly. At most 45 choose 2 = 990 combinations.
      for (var i = 0; i < remaining.length; i++) {
        if (need == 1) {
          score([...boardSoFar, remaining[i]]);
          continue;
        }
        for (var j = i + 1; j < remaining.length; j++) {
          score([...boardSoFar, remaining[i], remaining[j]]);
        }
      }
    } else {
      // Preflop: Monte-Carlo the 5-card runout.
      final rng = random ?? Random();
      final pool = [...remaining];
      for (var t = 0; t < preflopSamples; t++) {
        for (var k = 0; k < need; k++) {
          final idx = k + rng.nextInt(pool.length - k);
          final tmp = pool[k];
          pool[k] = pool[idx];
          pool[idx] = tmp;
        }
        score([...boardSoFar, ...pool.take(need)]);
      }
    }

    return [for (final w in wins) w / trials];
  }
}
