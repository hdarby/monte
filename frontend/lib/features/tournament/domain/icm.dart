/// The Independent Chip Model: converts chip stacks into **tournament-dollar
/// equity** given the remaining payouts. This is what makes chips non-linear —
/// doubling your stack less than doubles your equity, which is why good players
/// tighten near the money.
///
/// [equities] uses the standard **Malmuth-Harville** finish-order recursion:
/// P(player i finishes first) = stack_i / total; condition on each possible
/// first-place finisher and recurse over the rest for the next payout. Recursion
/// depth is the number of paid places, so it's exact and cheap at the final-table
/// scale where ICM actually bites. For fields larger than [_exactLimit] players
/// it falls back to a chip-proportional approximation — early in a big MTT the
/// money is far away and ICM ≈ chip-EV anyway, so the error is negligible where
/// it doesn't matter and exact where it does.
class Icm {
  const Icm._();

  /// Above this many live players, use the chip-proportional approximation
  /// instead of the exact (factorial-in-depth) recursion.
  static const int _exactLimit = 10;

  /// Tournament-dollar equity for each stack in [stacks], given the place-indexed
  /// [payouts] (index 0 = 1st). Result is parallel to [stacks].
  static List<double> equities(List<int> stacks, List<int> payouts) {
    final n = stacks.length;
    if (n == 0) return const [];
    final total = stacks.fold<int>(0, (a, b) => a + b);
    if (total <= 0) return List<double>.filled(n, 0);
    if (payouts.isEmpty) return List<double>.filled(n, 0);

    // Large field: chip-proportional share of the whole remaining prize pool.
    if (n > _exactLimit) {
      final pool = payouts.fold<int>(0, (a, b) => a + b);
      return [for (final s in stacks) (s / total) * pool];
    }

    final out = List<double>.filled(n, 0);
    _accumulate(stacks, payouts, out, 1.0, <int>{});
    return out;
  }

  /// Recursively assigns the current top payout to each still-standing candidate
  /// weighted by their conditional P(finish next), accumulating into [out].
  /// [eliminated] holds indices already assigned a (better) place this branch;
  /// [prob] is the probability of reaching this branch.
  static void _accumulate(
    List<int> stacks,
    List<int> payouts,
    List<double> out,
    double prob,
    Set<int> eliminated,
  ) {
    final placeIndex = eliminated.length;
    if (placeIndex >= payouts.length) return; // no more paid places to assign

    var remainingChips = 0;
    for (var i = 0; i < stacks.length; i++) {
      if (!eliminated.contains(i)) remainingChips += stacks[i];
    }
    if (remainingChips <= 0) return;

    for (var i = 0; i < stacks.length; i++) {
      if (eliminated.contains(i) || stacks[i] <= 0) continue;
      final pNext = stacks[i] / remainingChips;
      final branch = prob * pNext;
      out[i] += branch * payouts[placeIndex];
      if (placeIndex + 1 < payouts.length) {
        _accumulate(stacks, payouts, out, branch, {...eliminated, i});
      }
    }
  }

  /// The **bubble factor** for [hero]: how many dollars are at risk per dollar to
  /// be won on an all-in — `(equity lost by busting) / (equity gained by
  /// doubling)`. `1.0` is chip-neutral; `> 1.0` means losing hurts more than
  /// winning helps, so the hero should tighten (the essence of ICM pressure).
  ///
  /// Doubling moves `stack` chips from the rest of the field (pro-rata) to the
  /// hero; busting sends them the other way. Clamped to a sane band.
  static double bubbleFactor(List<int> stacks, List<int> payouts, int hero) {
    final s = stacks[hero];
    if (s <= 0) return 1.0;
    final eqNow = equities(stacks, payouts)[hero];
    final eqUp = equities(_transfer(stacks, hero, s), payouts)[hero];
    final eqDown = equities(_transfer(stacks, hero, -s), payouts)[hero];
    final gain = eqUp - eqNow;
    final loss = eqNow - eqDown;
    if (gain <= 1e-9) return 1.0;
    return (loss / gain).clamp(0.5, 5.0);
  }

  /// Returns a copy of [stacks] with [delta] chips moved to [hero] from (or, if
  /// negative, to) the rest of the field, distributed pro-rata by stack. The
  /// hero's stack is clamped to `>= 0` and never exceeds the total chips.
  static List<int> _transfer(List<int> stacks, int hero, int delta) {
    final out = List<int>.of(stacks);
    final othersTotal = out.fold<int>(0, (a, b) => a + b) - out[hero];
    out[hero] = (out[hero] + delta).clamp(0, out.fold<int>(0, (a, b) => a + b));
    if (othersTotal <= 0) return out;
    var toSpread = -delta; // others gain when hero loses, and vice versa
    for (var i = 0; i < out.length; i++) {
      if (i == hero) continue;
      final share = (toSpread * (stacks[i] / othersTotal)).round();
      out[i] = (out[i] + share).clamp(0, 1 << 30);
    }
    return out;
  }
}
