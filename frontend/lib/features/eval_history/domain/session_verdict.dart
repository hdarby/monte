import 'package:meta/meta.dart';

import 'package:monte/features/eval_history/domain/session_report.dart';

/// How badly a finding misses, which is what decides where it appears.
enum Severity { good, bad, ugly }

/// One line of the verdict.
@immutable
class Finding {
  const Finding(this.severity, this.headline, this.detail);
  final Severity severity;
  final String headline;
  final String detail;
}

/// Turns a report into a verdict: what went well, what did not, and the one
/// thing to fix next.
///
/// The report was all evidence and no conclusion. Six tables of frequencies
/// leave the reader to work out which number matters, and the number that
/// matters is rarely the one furthest from its band — a small-blind completion
/// rate can be wildly "off" and cost nothing, while a five-point aggression
/// shortfall quietly costs a stack a session. So findings are ranked by
/// *consequence*, not by distance from target.
class SessionVerdict {
  const SessionVerdict._();

  /// Every finding, worst first.
  static List<Finding> of(SessionReport r) {
    final out = <Finding>[];

    void judge({
      required String name,
      required double value,
      required double lo,
      required double hi,
      required int sample,
      required int minSample,
      required double weight,
      String? tooLow,
      String? tooHigh,
      String? praise,
    }) {
      if (sample < minSample) return;
      final v = value.toStringAsFixed(1);
      if (value >= lo && value <= hi) {
        if (praise != null) {
          out.add(Finding(Severity.good, '$name $v%', praise));
        }
        return;
      }
      final miss = value < lo ? (lo - value) / lo : (value - hi) / hi;
      final sev = miss * weight >= 0.35 ? Severity.ugly : Severity.bad;
      final why = value < lo ? tooLow : tooHigh;
      out.add(Finding(sev, '$name $v%', why ?? 'outside the $lo-$hi% band'));
    }

    judge(
      name: 'Open-limp',
      value: r.limpPct,
      lo: 0,
      hi: 2,
      sample: r.firstInSpots,
      minSample: 12,
      weight: 1.0,
      tooHigh: 'First in, it is raise or fold. Limping forfeits the chance to '
          'win it there, invites the field in behind you, and caps your range.',
      praise: 'First in, you raised or folded. This is the discipline the rest '
          'of the game is built on.',
    );
    judge(
      name: 'PFR',
      value: r.pfrPct,
      lo: 15,
      hi: 24,
      sample: r.hands,
      minSample: 40,
      weight: 0.9,
      tooLow: 'You are entering pots without the initiative, which is the '
          'expensive way to play a good hand.',
      tooHigh: 'Raising more than you can defend against a 3-bet.',
      praise: 'Entering pots with the initiative.',
    );
    judge(
      name: 'WWSF',
      value: r.wwsfPct,
      lo: 43,
      hi: 55,
      sample: r.sawFlop,
      minSample: 25,
      weight: 0.9,
      tooLow: 'You are only winning pots when you make a hand. Half of poker '
          'is taking the ones nobody wants.',
      praise: 'Winning your share of the pots you contest.',
    );
    judge(
      name: 'VPIP',
      value: r.vpipPct,
      lo: 20,
      hi: 30,
      sample: r.hands,
      minSample: 40,
      weight: 0.7,
      tooLow: 'Folding too much preflop; the blinds grind you down.',
      tooHigh: 'Playing too many hands out of position.',
      praise: 'Hand selection is where it should be.',
    );
    judge(
      name: 'Fold to 3-bet',
      value: r.foldTo3BetPct,
      lo: 45,
      hi: 65,
      sample: r.faced3Bet,
      minSample: 10,
      weight: 0.7,
      tooLow: 'You are continuing against re-raises far too often.',
      tooHigh: 'Folding to 3-bets so readily that raising becomes a liability.',
    );
    judge(
      name: 'Fold BB to a steal',
      value: r.bbFoldToStealPct,
      lo: 35,
      hi: 58,
      sample: r.bbFacedSteal,
      minSample: 10,
      weight: 0.6,
      tooHigh: 'Your big blind is free money for anyone who opens.',
      praise: 'Defending the big blind at about the right rate.',
    );
    judge(
      name: 'Steal attempt',
      value: r.stealPct,
      lo: 32,
      hi: 50,
      sample: r.stealChances,
      minSample: 12,
      weight: 0.6,
      tooLow: 'Passing up unopened pots in late position is money left behind.',
      praise: 'Attacking unopened pots from late position.',
    );

    // The non-showdown line, which is the passivity leak in one number.
    if (r.sawFlop >= 20) {
      out.add(r.nonShowdownBb < 0
          ? Finding(
              Severity.ugly,
              'Non-showdown ${r.nonShowdownBb.toStringAsFixed(0)} bb',
              'You are not taking pots away. Every profit has to come from '
                  'holding the best hand, which is half a strategy.')
          : Finding(
              Severity.good,
              'Non-showdown +${r.nonShowdownBb.toStringAsFixed(0)} bb',
              'You are winning pots uncontested. That is aggression paying.'));
    }

    const order = {Severity.ugly: 0, Severity.bad: 1, Severity.good: 2};
    out.sort((a, b) => order[a.severity]!.compareTo(order[b.severity]!));
    return out;
  }

  /// The single thing to work on next — the worst finding, or null if clean.
  static Finding? nextFix(List<Finding> findings) =>
      findings.where((f) => f.severity != Severity.good).firstOrNull;
}
