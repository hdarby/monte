import 'package:meta/meta.dart';

import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/hand_strength.dart';

/// Turns target preflop *frequencies* (VPIP / PFR / 3-bet) into *strength
/// thresholds* over [HandStrength.preflopOf].
///
/// Calibration is by construction: enumerate all 1326 two-card combos, sort by
/// strength, and pick the cutoff whose top fraction matches each target. A hand
/// qualifies for an action when its preflop strength is `>=` the threshold, so a
/// `vpipTarget` of 0.24 admits the strongest ~24% of deals.
@immutable
class PreflopRanges {
  const PreflopRanges({
    required this.vpip,
    required this.pfr,
    required this.threeBet,
  });

  /// Strength cutoffs (higher = tighter). `pfr >= vpip` and `threeBet >= pfr`
  /// whenever the targets are ordered that way.
  final double vpip;
  final double pfr;
  final double threeBet;

  factory PreflopRanges.forTargets({
    required double vpipTarget,
    required double pfrTarget,
    required double threeBetTarget,
  }) {
    final dist = _distribution;
    return PreflopRanges(
      vpip: _thresholdFor(dist, vpipTarget),
      pfr: _thresholdFor(dist, pfrTarget),
      threeBet: _thresholdFor(dist, threeBetTarget),
    );
  }

  /// The strength cutoff admitting the top [fraction] of all starting hands.
  static double thresholdForFraction(double fraction) =>
      _thresholdFor(_distribution, fraction);

  /// All 1326 combo strengths, sorted descending (computed once, cached).
  static final List<double> _distribution = _computeDistribution();

  static List<double> _computeDistribution() {
    final cards = [
      for (final r in Rank.values)
        for (final s in Suit.values) Card(r, s),
    ];
    final out = <double>[];
    for (var i = 0; i < cards.length; i++) {
      for (var j = i + 1; j < cards.length; j++) {
        out.add(HandStrength.preflopOf(cards[i], cards[j]));
      }
    }
    out.sort((a, b) => b.compareTo(a));
    return out;
  }

  /// The strength cutoff admitting the top [fraction] of combos.
  static double _thresholdFor(List<double> sortedDesc, double fraction) {
    if (fraction <= 0) return 1.01; // nothing qualifies
    if (fraction >= 1) return -0.01; // everything qualifies
    final n = sortedDesc.length;
    final idx = (fraction * n).floor().clamp(1, n) - 1;
    return sortedDesc[idx];
  }
}
