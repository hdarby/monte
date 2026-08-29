import 'package:monte/core/util/format.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';
import 'package:monte/features/eval_history/domain/session_report.dart';
import 'package:monte/features/eval_history/domain/session_verdict.dart';
import 'package:monte/features/tournament/domain/tournament_result.dart';

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
  ///
  /// [place]/[entrants] are this tournament's own result — separate from
  /// [career], which is the aggregate across every event ever finished. Null
  /// for a cash-table session (no tournament to report a finish for).
  static String of(
    SessionReport r, {
    List<(EvalDecision, EvalHand)> worst = const [],
    SessionReport? previous,
    List<(String, SessionReport)> bands = const [],
    List<CareerRow> career = const [],
    int? place,
    int? entrants,
  }) {
    final b = StringBuffer();
    final label = r.sessionId == null ? 'Baseline' : 'Session ${r.sessionId}';
    b.writeln('# $label');
    b.writeln();
    b.writeln('${r.hands} hands · ${r.decisionCount} graded decisions');
    b.writeln();

    // --- This event's own result, before anything else ----------------------
    // The most-asked question walking away from a tournament — "how did I do,
    // and what did it pay" — and it was previously answered nowhere in this
    // report; only in the results overlay the player taps past to get here.
    if (place != null) {
      final field = entrants == null ? '' : ' of $entrants';
      b.writeln(
        place == 1
            ? '**You won it$field.**'
            : '**Finished ${ordinal(place)}$field.**',
      );
      b.writeln();
      b.writeln();
    }

    // --- The verdict, first --------------------------------------------------
    // Six tables of frequencies leave the reader to work out which number
    // matters. This says it. Findings are ranked by consequence rather than by
    // distance from target — a small-blind completion rate can be wildly off
    // and cost nothing, while five points of missing aggression quietly costs a
    // stack a session.
    final findings = SessionVerdict.of(r);
    if (findings.isNotEmpty) {
      void section(String title, Severity sev) {
        final rows = findings.where((f) => f.severity == sev).toList();
        if (rows.isEmpty) return;
        b.writeln('### $title');
        b.writeln();
        for (final f in rows) {
          b.writeln('- **${f.headline}** — ${f.detail}');
        }
        b.writeln();
      }

      b.writeln('## The verdict');
      b.writeln();
      section('The ugly', Severity.ugly);
      section('The bad', Severity.bad);
      section('The good', Severity.good);

      final fix = SessionVerdict.nextFix(findings);
      b.writeln(
        fix == null
            ? '**Nothing to fix.** Every measured frequency landed in its band. '
                  'Play more hands and let the sample grow.'
            : '**Fix next: ${fix.headline}.** One thing, not seven — the rest '
                  'will follow it.',
      );
      b.writeln();
    }

    // --- Was it luck? ---------------------------------------------------
    b.writeln('## Result');
    b.writeln();
    b.writeln('| | |');
    b.writeln('|---|---|');
    b.writeln('| Net | ${_bb(r.netBb)} (${_r1(r.bbPer100)} bb/100) |');
    b.writeln('| All-in adjusted | ${_r1(r.allInEvPer100)} bb/100 |');
    b.writeln('| Luck | ${_bb(r.luckBb)} |');
    b.writeln();
    b.writeln(
      r.luckBb < -20
          ? '_You ran below expectation. Some of this result is not your doing._'
          : r.luckBb > 20
          ? '_You ran above expectation. Some of this result is not your doing._'
          : '_Close to expectation — this result is real._',
    );
    b.writeln();

    // --- The passivity picture -------------------------------------------
    b.writeln('## Red line / blue line');
    b.writeln();
    b.writeln('| Won at showdown | Won without one |');
    b.writeln('|---|---|');
    b.writeln('| ${_bb(r.showdownBb)} | **${_bb(r.nonShowdownBb)}** |');
    b.writeln();
    b.writeln(
      r.nonShowdownBb < 0
          ? '_Negative without a showdown: you are not taking pots away. Every '
                'profit has to come from holding the best hand._'
          : '_Positive without a showdown: you are winning pots uncontested. '
                'That is aggression paying._',
    );
    b.writeln();

    // --- By table size ------------------------------------------------------
    // Before the pooled figures, because the pooled figures are the misleading
    // ones: a tournament that starts nine-handed and ends heads-up reports one
    // VPIP true of neither stretch.
    final shown = bands.where((e) => e.$2.hands >= 15).toList();
    if (shown.length > 1) {
      b.writeln('## By table size');
      b.writeln();
      b.writeln('| Band | Hands | VPIP | PFR | Limp | WWSF |');
      b.writeln('|---|---|---|---|---|---|');
      for (final (name, x) in shown) {
        b.writeln(
          '| $name | ${x.hands} | ${_r1(x.vpipPct)}% | '
          '${_r1(x.pfrPct)}% | ${_r1(x.limpPct)}% | ${_r1(x.wwsfPct)}% |',
        );
      }
      b.writeln();
      final skipped = bands.length - shown.length;
      b.writeln(
        '_Correct play differs enormously between these — roughly 23% '
        'VPIP nine-handed against 80% heads-up — so the pooled figures below '
        'describe none of them exactly. Read the band you care about._'
        '${skipped > 0 ? ' $skipped band(s) hidden for too few hands.' : ''}',
      );
      b.writeln();
    }

    // --- The rules --------------------------------------------------------
    b.writeln(shown.length > 1 ? '## All tables pooled' : '## The rules');
    b.writeln();
    b.writeln('| Metric | You | Target |');
    b.writeln('|---|---|---|');
    _row(
      b,
      'Open-limp (first in, not SB)',
      '${_r1(r.limpPct)}% of ${r.firstInSpots}',
      '0%',
      previous?.limpPct,
    );
    if (r.sbFirstIn > 0) {
      // Completing the small blind is often correct — three to one on half a
      // bet, better still with an ante — so it gets its own row rather than
      // being counted as a limp.
      _row(
        b,
        'SB complete (folded to you)',
        '${_r1(r.sbCompletePct)}% of ${r.sbFirstIn}',
        'often right',
        previous?.sbCompletePct,
      );
    }
    _row(b, 'VPIP', '${_r1(r.vpipPct)}%', '~23%', previous?.vpipPct);
    _row(b, 'PFR', '${_r1(r.pfrPct)}%', '~18%', previous?.pfrPct);
    _row(
      b,
      'WWSF',
      '${_r1(r.wwsfPct)}% of ${r.sawFlop}',
      '45-50%',
      previous?.wwsfPct,
    );
    _row(b, '3-bet', '${_r1(r.threeBetPct)}%', '6-9%', previous?.threeBetPct);
    _row(
      b,
      'Fold to 3-bet',
      '${_r0(r.foldTo3BetPct)}% of ${r.faced3Bet}',
      '50-60%',
      previous?.foldTo3BetPct,
    );
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
        'UTG',
        'UTG1',
        'UTG2',
        'MP',
        'MP1',
        'MP2',
        'LJ',
        'HJ',
        'CO',
        'BTN',
        'SB',
        'BB',
      ];
      final seats = r.rfiBySeat.keys.toList()
        ..sort((a, b) {
          final ia = order.indexOf(a), ib = order.indexOf(b);
          return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
        });
      for (final k in seats) {
        final v = r.rfiBySeat[k]!;
        final pct = v.$2 == 0 ? null : 100 * v.$3 / v.$2;
        b.writeln(
          '| $k | ${v.$1} | ${v.$2} | ${v.$3} | '
          '${pct == null ? '—' : '${_r0(pct.toDouble())}%'} |',
        );
      }
      b.writeln();
      b.writeln(
        '_Early seats should open tightest, the button widest. A flat '
        'or inverted curve means the hands you play most come from the '
        'hardest chairs._',
      );
      b.writeln();
    }

    // --- The blind battle -------------------------------------------------
    if (r.stealChances > 0 || r.bbFacedSteal > 0 || r.sbFacedSteal > 0) {
      b.writeln('## The blind battle');
      b.writeln();
      b.writeln('| | You | Target |');
      b.writeln('|---|---|---|');
      b.writeln(
        '| Steal attempt (CO/BTN/SB, folded to you) | '
        '**${_r0(r.stealPct)}% of ${r.stealChances}** | 35-45% |',
      );
      b.writeln(
        '| ...taken without a flop | ${_r0(r.stealWinPct)}% | 50-60% |',
      );
      b.writeln(
        '| Fold BB to a lone raiser | '
        '**${_r0(r.bbFoldToStealPct)}% of ${r.bbFacedSteal}** | 40-55% |',
      );
      b.writeln('| ...3-bet instead | ${r.bbThreeBet} | |');
      b.writeln(
        '| Fold SB to a lone raiser | '
        '**${_r0(r.sbFoldToStealPct)}% of ${r.sbFacedSteal}** | 60-75% |',
      );
      b.writeln('| ...3-bet instead | ${r.sbThreeBet} | |');
      b.writeln();
      b.writeln(
        '_The small blind folds more than the big blind and should: '
        'worse odds, and out of position for the rest of the hand. Defending '
        'it by calling is the expensive habit; 3-betting or folding is the '
        'cheap one._',
      );
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
      b.writeln(
        '**${_r1(r.evLostBb)} bb given up**, '
        '${r.evLostPerDecision.toStringAsFixed(2)} per decision.',
      );
      b.writeln();
      b.writeln('| Street | bb lost | | Action | bb lost |');
      b.writeln('|---|---|---|---|---|');
      final acts = r.evLostByAction.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      const streets = ['preflop', 'flop', 'turn', 'river'];
      for (var i = 0; i < streets.length; i++) {
        final a = i < acts.length ? acts[i] : null;
        b.writeln(
          '| ${streets[i]} | ${_r1(r.evLostByStreet[streets[i]] ?? 0)} '
          '| | ${a?.key ?? ''} | ${a == null ? '' : _r1(a.value)} |',
        );
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
        b.writeln(
          '- **You held** ${me?.holeCards.join(' ') ?? '?'}'
          '${h.board.isEmpty ? '' : ' on `${h.board.join(' ')}`'}',
        );
        b.writeln(
          '- Pot ${_r0(d.potBb)} bb, ${_r0(d.toCallBb)} bb to call, '
          'equity ${_r0(d.equity * 100)}%'
          '${d.potOdds == null ? '' : ', needing ${_r0(d.potOdds! * 100)}%'}',
        );
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
      b.writeln(
        'You busted holding **${me?.holeCards.join(' ') ?? '?'}**'
        '${bust.board.isEmpty ? ' before a flop' : ' on `${bust.board.join(' ')}`'}.',
      );
      final others = bust.players.where((p) => p.id != r.playerId && !p.folded);
      for (final o in others) {
        b.writeln(
          '- ${o.name}: ${o.holeCards.join(' ')}'
          '${o.madeHand == null ? '' : ' (${o.madeHand})'}',
        );
      }
      b.writeln();
    }
    // --- Career ---------------------------------------------------------
    //   if (career.isNotEmpty) {
    //     b.writeln('## Career');
    //     b.writeln();
    //     b.writeln('| Player | Events | Cashes | Cash % | In | Out | Net | ROI | '
    //         'Best | Faced you |');
    //     b.writeln('|---|---|---|---|---|---|---|---|---|---|');
    //     final you = career.where((c) => c.profileId == 'human');
    //     // The player first, then the field by ROI. You are reading this to find
    //     // out how you are doing; scrolling for your own row is absurd.
    //     for (final c in [...you, ...career.where((c) => c.profileId != 'human')]
    //         .take(31)) {
    //       b.writeln('| ${c.profileId == 'human' ? '**You**' : c.name} '
    //           '| ${c.played} | ${c.cashes} | ${_r0(c.cashRate)}% '
    //           '| \$${c.buyIns} | \$${c.won} | ${_bbMoney(c.net)} '
    //           '| ${c.roi >= 0 ? '+' : ''}${_r0(c.roi)}% '
    //           '| ${c.bestPlace >= 1 << 29 ? '—' : c.bestPlace} '
    //           '| ${c.facedYou} |');
    //     }
    //     b.writeln();
    //     b.writeln('_ROI is measured against money in, not events played, so one '
    //         'deep run in a big field outweighs a string of min-cashes. "Faced '
    //         'you" counts events where they shared a table with you — the rest '
    //         'they were somewhere else in the field._');
    //     if (career.length > 31) {
    //       b.writeln();
    //       b.writeln('_${career.length - 31} more not shown._');
    //     }
    //     b.writeln();
    //   }

    return b.toString();
  }

  static String _bbMoney(int v) => '${v >= 0 ? '+' : '-'}\$${v.abs()}';

  static void _row(
    StringBuffer b,
    String name,
    String value,
    String target,
    double? was,
  ) {
    final delta = was == null ? '' : ' _(was ${_r1(was)})_';
    b.writeln('| $name | **$value**$delta | $target |');
  }

  static String _bb(double v) =>
      '${v >= 0 ? '+' : ''}${v.toStringAsFixed(0)} bb';
  static String _r1(double v) => v.toStringAsFixed(1);
  static String _r0(double v) => v.toStringAsFixed(0);
}
