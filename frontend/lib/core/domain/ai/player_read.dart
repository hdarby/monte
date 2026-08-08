import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_stats.dart';

/// The two-way read on a seat: [mine] is how the hero reads that player, [ofMe]
/// is how that player (through their own style bias) reads the hero. [ofMe] is
/// null for the hero's own seat or an untracked observer.
class SeatRead {
  const SeatRead({required this.mine, this.ofMe});
  final PlayerRead mine;
  final PlayerRead? ofMe;
}

/// A human-readable read on a player, derived from their accumulated
/// [PlayerStats]. [description] is a sentence that reads after the player's name
/// (`name is description`), [tags] are short standout traits, and [stats] are
/// the headline numbers for the HUD. Pure — no UI dependency.
class PlayerRead {
  const PlayerRead({
    required this.description,
    required this.tags,
    required this.handsSeen,
    required this.confidence,
    required this.stats,
    required this.thin,
  });

  final String description;
  final List<String> tags;
  final int handsSeen;
  final double confidence;

  /// (label, value) headline stats, e.g. ('VPIP', '31%').
  final List<(String, String)> stats;

  /// Too few hands observed to trust the read.
  final bool thin;

  static String _pct(double r) => '${(r * 100).round()}%';

  /// Builds the objective read from [s]. With a thin sample it says so rather
  /// than over-reading noise.
  static PlayerRead of(PlayerStats s) => _build(
        vpip: s.vpipRate,
        pfr: s.pfrRate,
        threeBet: s.threeBetRate,
        steal: s.stealRate,
        cbet: s.cbetRate,
        foldToCbet: s.foldToCbetRate,
        foldBlindSteal: s.foldBlindStealRate,
        af: s.aggressionFactor,
        hands: s.hands.round(),
        confidence: s.confidence,
        established: s.established,
      );

  /// How [observer] would read a player with true stats [s] — a subjective read,
  /// warped by the observer's own style (a contrast effect: a nit thinks
  /// everyone is a maniac; a loose player thinks everyone is a nit). Only the
  /// perception-driving lines (looseness/aggression) are biased; standout traits
  /// still come from the real numbers.
  static PlayerRead perceivedBy(PlayerStats s, PlayerProfile observer) {
    final ref = observer.strategicBaseline;
    // Contrast against the observer's own baseline: they judge others relative
    // to themselves, so a tight observer over-reads looseness and vice versa.
    double contrast(double val, double own, double gain) =>
        (val + gain * (val - own)).clamp(0.0, 1.0);
    final pVpip = contrast(s.vpipRate, ref.vpipTarget, 0.55);
    final pPfr = contrast(s.pfrRate, ref.pfrTarget, 0.55);
    // A passive observer (low PFR) sees others as more aggressive postflop.
    final afBias = (0.20 - ref.pfrTarget).clamp(-0.15, 0.20);
    final pAf = s.aggressionFactor.isFinite
        ? (s.aggressionFactor * (1 + 1.6 * afBias)).clamp(0.0, 12.0)
        : s.aggressionFactor;
    return _build(
      vpip: pVpip,
      pfr: pPfr,
      threeBet: s.threeBetRate,
      steal: s.stealRate,
      cbet: s.cbetRate,
      foldToCbet: s.foldToCbetRate,
      foldBlindSteal: s.foldBlindStealRate,
      af: pAf,
      hands: s.hands.round(),
      confidence: s.confidence,
      established: s.established,
    );
  }

  static PlayerRead _build({
    required double vpip,
    required double pfr,
    required double threeBet,
    required double steal,
    required double cbet,
    required double foldToCbet,
    required double foldBlindSteal,
    required double af,
    required int hands,
    required double confidence,
    required bool established,
  }) {
    final lines = <(String, String)>[
      ('VPIP', _pct(vpip)),
      ('PFR', _pct(pfr)),
      ('3B', _pct(threeBet)),
      ('Stl', _pct(steal)),
      ('CB', _pct(cbet)),
      ('AF', af.isFinite ? af.toStringAsFixed(1) : '∞'),
    ];
    if (!established) {
      final need = PlayerStats.baselineHands.round();
      return PlayerRead(
        description: hands == 0
            ? 'unread — no hands observed yet'
            : 'still building a read ($hands of $need hands)',
        tags: const [],
        handsSeen: hands,
        confidence: confidence,
        stats: lines,
        thin: true,
      );
    }

    final loose = vpip >= 0.42
        ? 'very loose'
        : vpip >= 0.30
            ? 'loose'
            : vpip >= 0.22
                ? 'solid'
                : vpip >= 0.15
                    ? 'tight'
                    : 'very tight';
    final gap = vpip - pfr;
    final preAgg = pfr >= 0.24
        ? 'aggressive'
        : gap >= 0.16
            ? 'passive'
            : 'standard';
    final post = !af.isFinite || af >= 2.6
        ? 'very aggressive'
        : af >= 1.4
            ? 'aggressive'
            : af <= 0.7
                ? 'passive'
                : 'standard';
    final sticky = foldToCbet < 0.35;

    // The read grows more detailed as more hands accrue: the preflop read firms
    // up first, the postflop read needs more streets played, and the finer
    // behavioural tags only appear once there's a real sample behind them. Early
    // established reads stay deliberately terse rather than overclaiming.
    final buf = StringBuffer('$loose and $preAgg preflop');
    if (hands >= 30) {
      buf.write(', $post postflop');
      if (hands >= 45 && sticky) buf.write(' and hard to bluff');
    }
    final description = buf.toString();

    final tags = <String>[];
    if (hands >= 25) {
      if (threeBet >= 0.09) {
        tags.add('3-bets a lot');
      } else if (threeBet <= 0.035) {
        tags.add('rarely 3-bets');
      }
    }
    if (hands >= 35) {
      if (steal >= 0.55) tags.add('steals wide late');
      if (foldBlindSteal >= 0.72) tags.add('folds blinds to steals');
    }
    if (hands >= 45) {
      if (cbet >= 0.78) tags.add('c-bets relentlessly');
      if (foldToCbet >= 0.62) tags.add('folds to c-bets');
      if (post == 'passive' && sticky) tags.add('calling station');
    }

    return PlayerRead(
      description: description,
      tags: tags,
      handsSeen: hands,
      confidence: confidence,
      stats: lines,
      thin: false,
    );
  }
}
