import 'package:monte/features/eval_history/domain/eval_hand.dart';
import 'package:monte/features/eval_history/domain/session_report.dart';

/// Renders a [SessionReport] as the markdown review the player actually reads.
///
/// Pure — no Flutter — so the wording is unit-testable and the same text can be
/// shown on screen, copied out, or written to a file.
///
/// Every number is printed beside the band it should be in. A metric with no
/// target is trivia; a metric with one is coaching.
class SessionMarkdown {
  const SessionMarkdown._();

  /// [worst] are the player's costliest decisions, already sorted.
  static String of(
    SessionReport r, {
    List<(EvalDecision, EvalHand)> worst = const [],
    SessionReport? previous,
  }) {
    final b = StringBuffer();
    final label = r.sessionId == null ? 'Baseline' : 'Session ${r.sessionId}';
    b.writeln('# $label');
    b.writeln();
    b.writeln('${r.hands} hands · ${r.decisionCount} graded decisions');
    b.writeln();

    // --- Was it luck? ---------------------------------------------------
    b.writeln('## Result');
    b.writeln();
    b.writeln('| | |');
    b.writeln('|---|---|');
    b.writeln('| Net | ${_bb(r.netBb)} (${_r1(r.bbPer100)} bb/100) |');
    b.writeln('| All-in adjusted | ${_r1(r.allInEvPer100)} bb/100 |');
    b.writeln('| Luck | ${_bb(r.luckBb)} |');
    b.writeln();
    b.writeln(r.luckBb < -20
        ? '_You ran below expectation. Some of this result is not your doing._'
        : r.luckBb > 20
            ? '_You ran above expectation. Some of this result is not your doing._'
            : '_Close to expectation — this result is real._');
    b.writeln();

    // --- The passivity picture -------------------------------------------
    b.writeln('## Red line / blue line');
    b.writeln();
    b.writeln('| Won at showdown | Won without one |');
    b.writeln('|---|---|');
    b.writeln('| ${_bb(r.showdownBb)} | **${_bb(r.nonShowdownBb)}** |');
    b.writeln();
    b.writeln(r.nonShowdownBb < 0
        ? '_Negative without a showdown: you are not taking pots away. Every '
            'profit has to come from holding the best hand._'
        : '_Positive without a showdown: you are winning pots uncontested. '
            'That is aggression paying._');
    b.writeln();

    // --- The rules --------------------------------------------------------
    b.writeln('## The rules');
    b.writeln();
    b.writeln('| Metric | You | Target |');
    b.writeln('|---|---|---|');
    _row(b, 'Limp (first in)', '${_r1(r.limpPct)}% of ${r.firstInSpots}', '0%',
        previous?.limpPct);
    _row(b, 'VPIP', '${_r1(r.vpipPct)}%', '~23%', previous?.vpipPct);
    _row(b, 'PFR', '${_r1(r.pfrPct)}%', '~18%', previous?.pfrPct);
    _row(b, 'WWSF', '${_r1(r.wwsfPct)}% of ${r.sawFlop}', '45-50%',
        previous?.wwsfPct);
    _row(b, '3-bet', '${_r1(r.threeBetPct)}%', '6-9%', previous?.threeBetPct);
    _row(b, 'Fold to 3-bet', '${_r0(r.foldTo3BetPct)}% of ${r.faced3Bet}',
        '50-60%', previous?.foldTo3BetPct);
    b.writeln();

    // --- Position ----------------------------------------------------------
    if (r.rfiBySeat.isNotEmpty) {
      b.writeln('## Opening by seat');
      b.writeln();
      b.writeln('| Seat | Dealt | First in | Raised | |');
      b.writeln('|---|---|---|---|---|');
      // Table order, not frequency order — a positional curve is only readable
      // if the seats are in the order they act.
      const order = [
        'UTG', 'UTG1', 'UTG2', 'MP', 'MP1', 'MP2', 'LJ', 'HJ', 'CO', 'BTN',
        'SB', 'BB',
      ];
      final seats = r.rfiBySeat.keys.toList()
        ..sort((a, b) {
          final ia = order.indexOf(a), ib = order.indexOf(b);
          return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
        });
      for (final k in seats) {
        final v = r.rfiBySeat[k]!;
        final pct = v.$2 == 0 ? null : 100 * v.$3 / v.$2;
        b.writeln('| $k | ${v.$1} | ${v.$2} | ${v.$3} | '
            '${pct == null ? '—' : '${_r0(pct.toDouble())}%'} |');
      }
      b.writeln();
      b.writeln('_Early seats should open tightest, the button widest. A flat '
          'or inverted curve means the hands you play most come from the '
          'hardest chairs._');
      b.writeln();
    }

    // --- Rivers ------------------------------------------------------------
    if (r.riverFoldBySize.isNotEmpty) {
      b.writeln('## Facing a river bet');
      b.writeln();
      b.writeln('| Size | Faced | Folded |');
      b.writeln('|---|---|---|');
      for (final k in const ['<1/3', '1/3-2/3', '2/3-pot', 'overbet']) {
        final v = r.riverFoldBySize[k];
        if (v == null) continue;
        b.writeln('| $k | ${v.$1} | ${v.$2} |');
      }
      b.writeln();
      b.writeln('_Calling cheap is fine. Calling big with one pair is not._');
      b.writeln();
    }

    // --- What it cost -------------------------------------------------------
    if (r.decisionCount > 0) {
      b.writeln('## What it cost');
      b.writeln();
      b.writeln('**${_r1(r.evLostBb)} bb given up**, '
          '${r.evLostPerDecision.toStringAsFixed(2)} per decision.');
      b.writeln();
      b.writeln('| Street | bb lost | | Action | bb lost |');
      b.writeln('|---|---|---|---|---|');
      final acts = r.evLostByAction.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      const streets = ['preflop', 'flop', 'turn', 'river'];
      for (var i = 0; i < streets.length; i++) {
        final a = i < acts.length ? acts[i] : null;
        b.writeln('| ${streets[i]} | ${_r1(r.evLostByStreet[streets[i]] ?? 0)} '
            '| | ${a?.key ?? ''} | ${a == null ? '' : _r1(a.value)} |');
      }
      b.writeln();
    }

    // --- The hands ----------------------------------------------------------
    if (worst.isNotEmpty) {
      b.writeln('## Your costliest decisions');
      b.writeln();
      for (final (d, h) in worst) {
        final me = h.players.where((p) => p.id == d.playerId).firstOrNull;
        b.writeln('### ${_r1(d.evLost)} bb — ${d.street}');
        b.writeln();
        b.writeln('- **You held** ${me?.holeCards.join(' ') ?? '?'}'
            '${h.board.isEmpty ? '' : ' on `${h.board.join(' ')}`'}');
        b.writeln('- Pot ${_r0(d.potBb)} bb, ${_r0(d.toCallBb)} bb to call, '
            'equity ${_r0(d.equity * 100)}%'
            '${d.potOdds == null ? '' : ', needing ${_r0(d.potOdds! * 100)}%'}');
        b.writeln('- **You:** ${d.chosenLabel} (${_r1(d.chosenEv)} bb)');
        b.writeln('- **Better:** ${d.bestLabel} (${_r1(d.bestEv)} bb)');
        b.writeln();
      }
    }

    // --- The bustout ---------------------------------------------------------
    final bust = r.bustout;
    if (bust != null) {
      final me = bust.players.where((p) => p.id == r.playerId).firstOrNull;
      b.writeln('## How it ended');
      b.writeln();
      b.writeln('You busted holding **${me?.holeCards.join(' ') ?? '?'}**'
          '${bust.board.isEmpty ? ' before a flop' : ' on `${bust.board.join(' ')}`'}.');
      final others = bust.players.where((p) => p.id != r.playerId && !p.folded);
      for (final o in others) {
        b.writeln('- ${o.name}: ${o.holeCards.join(' ')}'
            '${o.madeHand == null ? '' : ' (${o.madeHand})'}');
      }
      b.writeln();
    }
    return b.toString();
  }

  static void _row(
      StringBuffer b, String name, String value, String target, double? was) {
    final delta = was == null ? '' : ' _(was ${_r1(was)})_';
    b.writeln('| $name | **$value**$delta | $target |');
  }

  static String _bb(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(0)} bb';
  static String _r1(double v) => v.toStringAsFixed(1);
  static String _r0(double v) => v.toStringAsFixed(0);
}
