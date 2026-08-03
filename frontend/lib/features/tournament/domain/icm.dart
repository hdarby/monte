import 'dart:typed_data';

/// The Independent Chip Model: converts chip stacks into **tournament-dollar
/// equity** given the remaining payouts. This is what makes chips non-linear —
/// doubling your stack less than doubles your equity, which is why good players
/// tighten near the money.
///
/// [equities] uses the standard **Malmuth-Harville** finish-order model:
/// P(player i finishes first) = stack_i / total; condition on each possible
/// first-place finisher and continue for the next payout. It's computed with a
/// subset DP over eliminated-sets (O(n·2^n), exact) rather than the naive O(n!)
/// order recursion, so it stays fast even at a full 9-handed final table where
/// ICM actually bites. For fields larger than [exactLimit] players it falls back
/// to a chip-proportional approximation — early in a big MTT the money is far
/// away and ICM ≈ chip-EV anyway, so the error is negligible where it doesn't
/// matter and exact where it does.
class Icm {
  const Icm._();

  /// Above this many live players, use the chip-proportional approximation
  /// instead of the exact (factorial-in-depth) recursion. Also the point below
  /// which [bubbleFactor] differs meaningfully from chip-neutral (1.0), so
  /// callers can skip the per-decision ICM work entirely above it.
  static const int exactLimit = 10;

  /// Tournament-dollar equity for each stack in [stacks], given the place-indexed
  /// [payouts] (index 0 = 1st). Result is parallel to [stacks].
  static List<double> equities(List<int> stacks, List<int> payouts) {
    final n = stacks.length;
    if (n == 0) return const [];
    final total = stacks.fold<int>(0, (a, b) => a + b);
    if (total <= 0) return List<double>.filled(n, 0);
    if (payouts.isEmpty) return List<double>.filled(n, 0);

    // Large field: chip-proportional share of the whole remaining prize pool.
    if (n > exactLimit) {
      final pool = payouts.fold<int>(0, (a, b) => a + b);
      return [for (final s in stacks) (s / total) * pool];
    }

    // Exact Malmuth-Harville via subset DP: `f[mask]` is the probability that
    // exactly the players in `mask` have taken the top places (in any order).
    // Collapsing the n! finish orderings into 2^n eliminated-sets turns the
    // recursion from O(n!) into O(n·2^n) — the difference between a 9-handed
    // final table grinding for minutes per decision and finishing in microseconds.
    final depth = payouts.length < n ? payouts.length : n;
    final size = 1 << n;
    final f = Float64List(size);
    f[0] = 1.0;
    final out = List<double>.filled(n, 0);
    for (var mask = 0; mask < size; mask++) {
      final p = f[mask];
      if (p == 0) continue;
      final placeIndex = _popcount(mask);
      if (placeIndex >= depth) continue;
      var sumMask = 0;
      for (var i = 0; i < n; i++) {
        if ((mask & (1 << i)) != 0) sumMask += stacks[i];
      }
      final remaining = total - sumMask;
      if (remaining <= 0) continue;
      final pay = payouts[placeIndex];
      final expand = placeIndex + 1 < depth;
      for (var i = 0; i < n; i++) {
        if ((mask & (1 << i)) != 0 || stacks[i] <= 0) continue;
        final branch = p * (stacks[i] / remaining);
        out[i] += branch * pay;
        if (expand) f[mask | (1 << i)] += branch;
      }
    }
    return out;
  }

  static int _popcount(int x) {
    var c = 0;
    var v = x;
    while (v != 0) {
      v &= v - 1;
      c++;
    }
    return c;
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
