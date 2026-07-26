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
/// [forFieldSize] generates a conventional top-heavy curve: roughly the top ~15%
/// of the field is paid (with sensible small-field floors), and prizes decay
/// geometrically so 1st earns the most. It's a believable stand-in for a real
/// published payout table, not a copy of any specific one.
@immutable
class PayoutStructure {
  const PayoutStructure(this.fractions);

  final List<double> fractions;

  int get paidPlaces => fractions.length;

  factory PayoutStructure.forFieldSize(int entrants) {
    final places = _paidPlacesFor(entrants);
    // Geometric decay, normalized. ratio 0.62 over 3 places ≈ 50/30/20.
    const ratio = 0.62;
    final weights = [for (var k = 0; k < places; k++) pow(ratio, k).toDouble()];
    final sum = weights.fold<double>(0, (a, b) => a + b);
    return PayoutStructure([for (final w in weights) w / sum]);
  }

  static int _paidPlacesFor(int entrants) {
    if (entrants <= 2) return 1;
    if (entrants <= 5) return 2;
    if (entrants <= 9) return 3;
    // ~top 15% of the field, at least 3, never the whole field.
    return (entrants * 0.15).round().clamp(3, entrants - 1);
  }

  /// The chip prize for a 1-indexed [place] out of [prizePool]. Each place is
  /// floored to whole chips and any rounding remainder is pushed onto 1st, so
  /// the payouts always sum exactly to [prizePool].
  int payoutForPlace(int place, int prizePool) {
    if (place < 1 || place > paidPlaces) return 0;
    final floors = [for (final f in fractions) (f * prizePool).floor()];
    final remainder = prizePool - floors.fold<int>(0, (a, b) => a + b);
    if (place == 1) return floors[0] + remainder;
    return floors[place - 1];
  }

  /// The full payout vector for [prizePool] (index 0 = 1st), summing to it.
  List<int> payouts(int prizePool) =>
      [for (var p = 1; p <= paidPlaces; p++) payoutForPlace(p, prizePool)];
}
