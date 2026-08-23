import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_stats.dart';

/// The two-way read on a seat: [mine] is how the hero reads that player, [ofMe]
/// is how that player (through their own style bias) reads the hero. [ofMe] is
/// null for the hero's own seat or an untracked observer.
class SeatRead {
  const SeatRead({required this.mine, this.ofMe, this.live = const []});
  final PlayerRead mine;
  final PlayerRead? ofMe;

  /// Read-outs that come from the state of *this session* rather than from
  /// accumulated history — tilt, a heater, and how well they have you pegged.
  ///
  /// Kept apart from [PlayerRead.tags] because the two decay differently: a tag
  /// is a hundred hands of evidence and a live flag can be true this orbit and
  /// false the next. Presenting them identically would make the volatile ones
  /// look as settled as the durable ones.
  final List<LiveRead> live;
}

/// A short-lived read on a seat, with the urgency to colour it by.
class LiveRead {
  const LiveRead(this.label, this.kind);
  final String label;
  final LiveReadKind kind;
}

enum LiveReadKind {
  /// Stack geometry: who can bust whom, and who is short enough to be jamming.
  /// Pure tournament information, and the most actionable thing at the table —
  /// whether a call ends your tournament changes every decision in the hand.
  stack,

  /// They are rattled — exploitable, and dangerous in the way a rattled player
  /// is dangerous.
  tilt,

  /// Running hot. Not a strategy read; a table-image one.
  rush,

  /// They have a strong, established read on *you*. The one to actually fear.
  danger,
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
        foldToBet: s.foldToBetRate,
        foldTo3bet: s.foldTo3betRate,
        squeeze: s.squeezeRate,
        wsd: s.wonAtShowdownRate,
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
      foldToBet: s.foldToBetRate,
      wsd: s.wonAtShowdownRate,
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
    required double foldToBet,
    double foldTo3bet = 0.55,
    double squeeze = 0.05,
    required double wsd,
    required int hands,
    required double confidence,
    required bool established,
  }) {
    final lines = <(String, String)>[
      ('VPIP', _pct(vpip)),
      ('PFR', _pct(pfr)),
      ('3B', _pct(threeBet)),
      ('CB', _pct(cbet)),
      ('F2B', _pct(foldToBet)),
      ('WSD', _pct(wsd)),
      ('AF', af.isFinite ? af.toStringAsFixed(1) : '∞'),
    ];
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

    // Sub-baseline reads: a read firms up in stages. Nothing at all at first;
    // an "impression" once you've shared a few hands; an "idea" after ~two
    // orbits; and only past the baseline is it a trusted read (the exploit
    // gate — [established] — still needs the full sample). The tentative
    // stages hedge the language so the model never over-claims.
    if (!established) {
      final need = PlayerStats.baselineHands.round();
      final String desc;
      if (hands == 0) {
        desc = 'unread — no hands observed yet';
      } else if (hands < 5) {
        desc = 'still forming a read ($hands of $need hands)';
      } else if (hands < 10) {
        desc = 'early impression — looks $loose and $preAgg preflop';
      } else {
        desc = 'getting an idea — plays $loose and $preAgg preflop';
      }
      return PlayerRead(
        description: desc,
        tags: const [],
        handsSeen: hands,
        confidence: confidence,
        stats: lines,
        thin: true,
      );
    }

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
      // The mirror image, and the more useful read: a blind they cannot steal
      // is a blind not worth attacking.
      if (foldBlindSteal <= 0.42) tags.add('defends blinds hard');
      if (foldTo3bet >= 0.68) tags.add('overfolds to 3-bets');
      if (foldTo3bet <= 0.35) tags.add('never folds to a 3-bet');
    }
    if (hands >= 25) {
      // The loudest recreational tell there is, and it was being computed and
      // thrown away: entering far more pots than you raise means limping.
      final gap = vpip - pfr;
      if (gap >= 0.18) {
        tags.add('limps a lot');
      } else if (gap <= 0.06 && vpip >= 0.15) {
        tags.add('raise or fold');
      }
    }
    if (hands >= 40) {
      // squeezeRate has been computed since it was written and read by nothing.
      if (squeeze >= 0.09) tags.add('squeezes light');
      if (squeeze <= 0.015) tags.add('never squeezes');
      if (af >= 4.0) tags.add('maniac');
      if (af <= 0.8) tags.add('pure passive');
    }
    if (hands >= 45) {
      if (cbet >= 0.78) tags.add('c-bets relentlessly');
      if (foldToCbet >= 0.62) tags.add('folds to c-bets');
      if (post == 'passive' && sticky) tags.add('calling station');
      // Fold-to-bet and won-at-showdown tell you how to attack them postflop.
      if (foldToBet >= 0.58) tags.add('gives up to pressure');
      if (wsd <= 0.42) tags.add('shows down weak');
      if (wsd >= 0.62) tags.add('only shows the nuts');
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
