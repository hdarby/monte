import 'dart:math';

import 'package:meta/meta.dart';

/// The prize pool for a tournament: everyone's buy-ins plus rebuys.
@immutable
class PrizePool {
  const PrizePool({
    required this.buyIn,
    required this.entrants,
    this.rebuys = 0,
  });

  final int buyIn;
  final int entrants;
  final int rebuys;

  int get total => buyIn * (entrants + rebuys);
}

/// How a prize pool is split by finish place. [fractions] is place-indexed
/// (index 0 = 1st) and sums to 1.0; its length is the number of paid places.
///
/// [forFieldSize] reproduces the shape of a real published WSOP table. Roughly
/// the top ~15% of the field is paid (with small-field floors), the last paid
/// place gets exactly [minCashBuyIns] buy-ins, and first place is capped at
/// [firstPlaceCapBuyIns] buy-ins.
///
/// Everything is expressed in **buy-ins**, which needs no prize-pool argument:
/// the pool is `buyIn · entrants`, so *x* buy-ins is exactly `x / entrants` of
/// the pool. At the Main Event's 10,000 buy-in and a 10,000-runner field that
/// makes the min cash 15,000 and the first-place cap 10,000,000 — the real
/// numbers — while the cap simply never binds on a small field, which is also
/// how real structures work.
@immutable
class PayoutStructure {
  const PayoutStructure(this.fractions);

  final List<double> fractions;

  int get paidPlaces => fractions.length;

  /// How top-heavy the curve is. 1.0 is plain Zipf (prize ∝ 1/place), which
  /// tracks the published Main Event table closely: against 2024's real
  /// 10,000 / 6.0M / 4.0M / 1.0M for 1st / 2nd / 3rd / 9th, this produces
  /// 10.0M / 5.7M / 3.8M / 1.3M. The previous curve was *geometric* (0.7^k),
  /// which paid 1st 23.3M and collapsed to the min cash by 30th place.
  static const _decay = 1.0;

  factory PayoutStructure.forFieldSize(
    int entrants, {
    double minCashBuyIns = 1.5,
    double firstPlaceCapBuyIns = 1000,
  }) {
    final places = _paidPlacesFor(entrants);
    if (places <= 1) return const PayoutStructure([1.0]);

    // The min-cash floor every paid place clears, as a fraction of the pool.
    // Capped so the top still takes the lion's share in a small field.
    final base = min(minCashBuyIns / entrants, 0.5 / places);
    final remaining = 1.0 - base * places;

    // A power-law overlay on top of that floor, shifted so it reaches **zero**
    // at the last paid place. That shift is what makes the min cash come out
    // exact rather than "the floor plus whatever the tail happens to add", and
    // it gives the long flat run of identical min-cashes a real table has.
    final weights = [
      for (var k = 0; k < places; k++) pow(k + 1, -_decay).toDouble(),
    ];
    final last = weights.last;
    final shifted = [for (final w in weights) w - last];
    final sum = shifted.fold<double>(0, (a, b) => a + b);
    final fractions = [
      for (final w in shifted) base + remaining * (w / sum),
    ];

    // Cap first place and push the overflow down the rest of the curve, keeping
    // the last place pinned to the min cash (the shifted weights are zero
    // there). Skipped when the cap would drop 1st below 2nd — on a small field
    // the winner is *supposed* to take a huge share, and a cap set in buy-ins
    // only bites once the pool is thousands of buy-ins deep.
    final cap = firstPlaceCapBuyIns / entrants;
    if (fractions[0] > cap && cap > fractions[1]) {
      final excess = fractions[0] - cap;
      final tail = sum - shifted[0];
      if (tail > 0) {
        fractions[0] = cap;
        for (var i = 1; i < places; i++) {
          fractions[i] += excess * (shifted[i] / tail);
        }
      }
    }
    return PayoutStructure(fractions);
  }

  static int _paidPlacesFor(int entrants) {
    if (entrants <= 2) return 1;
    if (entrants <= 5) return 2;
    if (entrants <= 9) return 3;
    // ~top 15% of the field, at least 3, never the whole field.
    return (entrants * 0.15).round().clamp(3, entrants - 1);
  }

  /// The chip prize for a 1-indexed [place] out of [prizePool].
  int payoutForPlace(int place, int prizePool) {
    if (place < 1 || place > paidPlaces) return 0;
    return payouts(prizePool)[place - 1];
  }

  /// The full payout vector for [prizePool] (index 0 = 1st), summing to it.
  ///
  /// Each place is **rounded** and the leftover is spread from 2nd place
  /// downward, a chip at a time. Both details matter: flooring every place and
  /// dumping the remainder onto 1st (what this used to do) overshot the
  /// first-place cap by the accumulated remainder — ~1,500 chips over a Main
  /// Event field — and shaved the min cash to 14,999 because `15000.0` floors
  /// to 14999 once floating point is involved. Leaving 1st and last alone keeps
  /// the cap and the min cash exactly on their advertised numbers.
  List<int> payouts(int prizePool) {
    final out = [for (final f in fractions) (f * prizePool).round()];
    var remainder = prizePool - out.fold<int>(0, (a, b) => a + b);
    if (remainder == 0 || out.length == 1) {
      if (remainder != 0) out[0] += remainder;
      return out;
    }
    final step = remainder > 0 ? 1 : -1;
    // Bounded: each sweep moves |remainder| by at least one per eligible place,
    // so this cannot spin even if some places are already at zero.
    var i = 1;
    var guard = remainder.abs() * 2 + out.length;
    while (remainder != 0 && guard-- > 0) {
      if (out[i] + step >= 0) {
        out[i] += step;
        remainder -= step;
      }
      if (++i >= out.length) i = 1;
    }
    if (remainder != 0) out[0] += remainder; // pathological pool; stay exact
    return out;
  }
}
