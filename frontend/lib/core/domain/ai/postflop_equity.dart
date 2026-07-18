import 'dart:math';

import 'package:monte/core/domain/ai/hand_range.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';

/// Range-aware postflop equity: the probability the hero's holding beats a hand
/// drawn from a plausible villain [HandRange] once the board is complete.
///
/// This is the honest, personality-agnostic substrate the policies build on —
/// "how good is my hand vs what the villain can hold here", including draw
/// equity (it plays the runout out). It reuses the real [HandEvaluator] so
/// there's one rulebook, mirroring the preflop table's Monte-Carlo approach.
///
/// v1 is a **heads-up approximation**: equity vs a single representative
/// continuing range. Multiway (equity vs several live ranges at once) is a later
/// refinement.
class PostflopEquity {
  const PostflopEquity._();

  /// Hero [hole] (2 cards) vs [villain] range on [board] (3–5 cards), in [0,1].
  ///
  /// On the river (board complete) the range is enumerated exactly; earlier
  /// streets Monte-Carlo the runout with [iterations] samples. Ties count as a
  /// half-win. Returns 0.5 when the range is empty (no information).
  static double equity(
    List<Card> hole,
    List<Card> board,
    HandRange villain, {
    int iterations = 200,
    Random? random,
  }) {
    final rng = random ?? Random();
    final dead = {...hole, ...board};
    // Villain combos that don't collide with the hero's cards or the board.
    final combos = [
      for (final c in villain.combos)
        if (!dead.contains(c.$1) && !dead.contains(c.$2)) c,
    ];
    if (combos.isEmpty) return 0.5;

    final need = 5 - board.length; // future board cards to deal

    // River: no runout — enumerate the whole range for an exact number.
    if (need <= 0) {
      var score = 0.0;
      final heroValue = HandEvaluator.evaluate([...hole, ...board]);
      for (final c in combos) {
        final villainValue = HandEvaluator.evaluate([c.$1, c.$2, ...board]);
        score += _wl(heroValue.compareTo(villainValue));
      }
      return score / combos.length;
    }

    final available = [
      for (final suit in Suit.values)
        for (final rank in Rank.values)
          if (!dead.contains(Card(rank, suit))) Card(rank, suit),
    ];

    var score = 0.0;
    for (var i = 0; i < iterations; i++) {
      final villain = combos[rng.nextInt(combos.length)];
      // Deal the runout from the cards left after removing this villain hand.
      final pool = [
        for (final c in available)
          if (c != villain.$1 && c != villain.$2) c,
      ];
      final runout = <Card>[];
      for (var k = 0; k < need; k++) {
        final idx = k + rng.nextInt(pool.length - k);
        final tmp = pool[k];
        pool[k] = pool[idx];
        pool[idx] = tmp;
        runout.add(pool[k]);
      }
      final full = [...board, ...runout];
      final hero = HandEvaluator.evaluate([...hole, ...full]);
      final vill = HandEvaluator.evaluate([villain.$1, villain.$2, ...full]);
      score += _wl(hero.compareTo(vill));
    }
    return score / iterations;
  }

  static double _wl(int cmp) => cmp > 0
      ? 1.0
      : cmp == 0
          ? 0.5
          : 0.0;

  /// Hero equity **share** against [opponents] independent hands, each drawn
  /// from the same [villain] range, on [board]. Returns the fraction of the pot
  /// the hero wins on average in [0,1] (tie for best → split among the tied).
  ///
  /// This is the honest multiway number: the hero must be best of *all*
  /// opponents to scoop, and a k-way tie pays 1/k. For [opponents] `<= 1` it
  /// delegates to the heads-up [equity]. Note this is genuinely — and correctly
  /// — lower than heads-up equity, but nowhere near the `equity^opponents`
  /// approximation it replaces (which double-counts and collapses strong hands).
  static double equityMultiway(
    List<Card> hole,
    List<Card> board,
    HandRange villain, {
    int opponents = 1,
    int iterations = 400,
    Random? random,
  }) {
    if (opponents <= 1) {
      return equity(hole, board, villain,
          iterations: iterations, random: random);
    }
    final rng = random ?? Random();
    final dead = {...hole, ...board};
    final combos = [
      for (final c in villain.combos)
        if (!dead.contains(c.$1) && !dead.contains(c.$2)) c,
    ];
    if (combos.isEmpty) return 0.5;

    final need = 5 - board.length;
    var score = 0.0;
    var valid = 0;
    for (var i = 0; i < iterations; i++) {
      // Draw `opponents` non-colliding villain hands from the range.
      final used = <Card>{...dead};
      final villains = <(Card, Card)>[];
      for (var v = 0; v < opponents; v++) {
        (Card, Card)? pick;
        for (var tries = 0; tries < 12; tries++) {
          final c = combos[rng.nextInt(combos.length)];
          if (!used.contains(c.$1) && !used.contains(c.$2)) {
            pick = c;
            break;
          }
        }
        if (pick == null) break; // couldn't seat this many distinct hands
        used
          ..add(pick.$1)
          ..add(pick.$2);
        villains.add(pick);
      }
      if (villains.length < opponents) continue; // skip crowded sample

      // Deal the runout from what's left.
      final pool = [
        for (final suit in Suit.values)
          for (final rank in Rank.values)
            if (!used.contains(Card(rank, suit))) Card(rank, suit),
      ];
      final runout = <Card>[];
      for (var k = 0; k < need; k++) {
        final idx = k + rng.nextInt(pool.length - k);
        final tmp = pool[k];
        pool[k] = pool[idx];
        pool[idx] = tmp;
        runout.add(pool[k]);
      }
      final full = [...board, ...runout];
      final heroValue = HandEvaluator.evaluate([...hole, ...full]);
      var better = 0;
      var tied = 0;
      for (final vh in villains) {
        final cmp = heroValue.compareTo(
          HandEvaluator.evaluate([vh.$1, vh.$2, ...full]),
        );
        if (cmp < 0) {
          better++;
        } else if (cmp == 0) {
          tied++;
        }
      }
      if (better == 0) score += 1.0 / (tied + 1); // split with any ties
      valid++;
    }
    return valid == 0 ? 0.5 : score / valid;
  }
}
