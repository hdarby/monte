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
///
/// **Pay jumps, not a continuous curve.** A real published table never lists
/// a distinct number for every one of 1,500 paid places — it lists a few
/// dozen *tiers* of tied places, with the last tier (the min cash) covering a
/// large share of the field. The fractions here are still derived from a
/// smooth decay curve internally (`_decay`, the cap logic below), but
/// [_flattenIntoTiers] is the step that turns that curve into the blocks of
/// identical payouts a real table actually shows — see its doc for how a
/// tier's shared value is chosen and where the min-cash tier's savings go.
/// Below [_tierSizes]'s `minPlacesForTiers` threshold every place is still
/// paid individually: pay jumps are a large-field phenomenon, and a small
/// tournament barely has room for a final table, let alone ties.
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
    return PayoutStructure(_flattenIntoTiers(fractions, base));
  }

  static int _paidPlacesFor(int entrants) {
    if (entrants <= 2) return 1;
    if (entrants <= 5) return 2;
    if (entrants <= 9) return 3;
    // ~top 15% of the field, at least 3, never the whole field.
    return (entrants * 0.15).round().clamp(3, entrants - 1);
  }

  /// Groups a smoothly-decaying per-place curve into **pay jumps**: blocks of
  /// consecutive places that all cash for exactly the same amount, the way a
  /// real published payout table reads. A large field never quotes 1,500
  /// distinct numbers — it quotes a few dozen tiers, with the last one, the
  /// min cash, covering a large share of the paid field (in the 2024 Main
  /// Event, roughly the bottom half of the money finishes at the flat $15,000
  /// floor). [smooth] must already be the final per-place curve (post first-
  /// place cap) so this only regroups, never re-derives, the shape.
  ///
  /// Every tier except the last is paid the **average** of the smooth curve
  /// across its place range — this is exactly what a real payout table does
  /// when several close finishes are collapsed onto one line, and it preserves
  /// the tier's total share exactly (an average redistributes a sum, it never
  /// changes it). The last tier is forced to the pure floor (`base`) instead of
  /// its average, because a real min-cash tier pays the advertised minimum
  /// exactly, not "the average of the last few hundred places" — the tail of
  /// the smooth curve sits just *above* the floor (only the very last place
  /// hits it exactly), so flattening it down frees up a small surplus, which
  /// is added back to the tier directly above the min cash. That is where a
  /// real pay jump chart shows the money going: the jump *out of* min cash is
  /// bigger than the smooth curve implies, and the min cash itself is flatter.
  static List<double> _flattenIntoTiers(List<double> smooth, double base) {
    final places = smooth.length;
    final tiers = _tierSizes(places);
    final out = List<double>.filled(places, 0);
    var start = 0;
    for (var t = 0; t < tiers.length; t++) {
      final size = tiers[t];
      final isLast = t == tiers.length - 1;
      final groupSum =
          smooth.sublist(start, start + size).fold<double>(0, (a, b) => a + b);
      final value = isLast ? base : groupSum / size;
      for (var i = start; i < start + size; i++) {
        out[i] = value;
      }
      start += size;
    }
    // The last tier's surplus above the pure floor, handed to the tier just
    // above it so the total payout is unchanged.
    final lastSize = tiers.last;
    final lastStart = places - lastSize;
    final surplus =
        smooth.sublist(lastStart).fold<double>(0, (a, b) => a + b) -
            base * lastSize;
    if (surplus > 0 && tiers.length > 1) {
      final priorSize = tiers[tiers.length - 2];
      final priorStart = lastStart - priorSize;
      final bump = surplus / priorSize;
      for (var i = priorStart; i < lastStart; i++) {
        out[i] += bump;
      }
    } else if (surplus > 0) {
      // No tier above the min cash to absorb it (the whole field is one min-
      // cash tier) — keep the total exact by handing it to first place.
      out[0] += surplus;
    }
    return out;
  }

  /// Sizes of each pay-jump tier, top to bottom, summing to [paidPlaces].
  ///
  /// Places pay individually near the top (a 2nd-place finish is never worth
  /// the same as 3rd), then tiers widen going down — reasoned rather than
  /// measured (a real table's exact groupings vary by series), in the same
  /// spirit as `OpenRanges.tableFactor`'s "a first stab, deliberately": the
  /// `1.6`× growth and the min-cash share below are a first pass, checkable
  /// against `payout_structure_test.dart`'s published-table numbers.
  static List<int> _tierSizes(int paidPlaces) {
    // Below this many paid places, a real table just lists every place
    // individually — pay jumps are a large-field phenomenon. A field this
    // small barely has room for a final table, let alone tiers of ties, which
    // is the other half of what "small tournaments, it doesn't matter" means.
    const minPlacesForTiers = 10;
    if (paidPlaces < minPlacesForTiers) return List.filled(paidPlaces, 1);

    // How much of the pay table is the flat min-cash tier. A real Main-Event-
    // scale structure spends roughly the bottom half of the money on min
    // cash; a smaller field has less room for it, so it scales down with the
    // number of paid places rather than being fixed.
    final minCashShare = paidPlaces >= 200
        ? 0.45
        : paidPlaces >= 50
            ? 0.35
            : 0.2;
    final minCashSize =
        (paidPlaces * minCashShare).round().clamp(1, paidPlaces - 3);
    final ladderTarget = paidPlaces - minCashSize;

    final tiers = <int>[];
    var placed = 0;
    // The very top is always individual — a 2nd-place finish is never tied
    // with 3rd on a real table. Ties only start appearing a few spots down.
    final uniqueTop = min(3, ladderTarget);
    for (var i = 0; i < uniqueTop; i++) {
      tiers.add(1);
    }
    placed += uniqueTop;
    var size = 2;
    while (placed < ladderTarget) {
      final take = min(size, ladderTarget - placed);
      tiers.add(take);
      placed += take;
      size = max(1, (size * 1.6).round());
    }
    tiers.add(paidPlaces - placed); // the min-cash tier takes the remainder
    return tiers;
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
