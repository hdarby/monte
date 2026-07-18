import 'dart:math';

import 'package:meta/meta.dart';

import 'package:monte/core/domain/ai/hand_range.dart';
import 'package:monte/core/domain/ai/postflop_equity.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';

/// The kind of action an [ActionEv] scores.
enum CoachAction { fold, check, call, bet, raise }

/// The estimated EV of one candidate action, in **net chips relative to
/// folding** (fold = 0).
@immutable
class ActionEv {
  const ActionEv({
    required this.kind,
    required this.label,
    required this.ev,
    this.toAmount,
    this.sizingTag,
    this.note,
  });

  final CoachAction kind;
  final String label;

  /// Total "bet-to" for a bet/raise (null for fold/check/call). The dialog
  /// re-formats it via [MoneyFormat].
  final int? toAmount;

  /// e.g. "⅔ pot", "All-in".
  final String? sizingTag;

  /// Net-chip EV vs. folding.
  final double ev;
  final String? note;

  /// The concrete engine action this suggestion submits when clicked / played.
  GameAction toGameAction() => switch (kind) {
    CoachAction.fold => const GameAction.fold(),
    CoachAction.check => const GameAction.check(),
    CoachAction.call => const GameAction.call(),
    CoachAction.bet =>
      sizingTag == 'all-in' ? const GameAction.allIn() : GameAction.bet(toAmount!),
    CoachAction.raise =>
      sizingTag == 'all-in' ? const GameAction.allIn() : GameAction.raise(toAmount!),
  };
}

/// How the opponents' perceived range splits against the hero's current hand.
@immutable
class RangeBreakdown {
  const RangeBreakdown({
    required this.combos,
    required this.beat,
    required this.tie,
    required this.lose,
    required this.beatClasses,
    required this.loseClasses,
  });

  final int combos;

  /// Fractions of the perceived-range combos the hero currently beats / ties /
  /// loses to (as of the present board — draws count as whatever they've made).
  final double beat;
  final double tie;
  final double lose;

  /// Representative made-hand classes in each bucket (e.g. "Two Pair", "Pair").
  final List<String> beatClasses;
  final List<String> loseClasses;
}

/// The status of one starting-hand cell in the 13×13 grid, relative to the
/// hero's current hand.
enum CellStatus {
  /// Not part of the opponents' perceived range.
  out,

  /// In range, but there's no board yet to compare (preflop).
  inRange,

  /// In range and the hero currently beats it.
  ahead,

  /// In range and the hero currently loses to it.
  behind,

  /// In range with a mix of beat/lose combos (e.g. suit-dependent).
  split,
}

/// One cell of the starting-hand grid (e.g. "AKs", "77", "T9o").
@immutable
class RangeCell {
  const RangeCell({
    required this.label,
    required this.row,
    required this.col,
    required this.inRange,
    required this.beat,
    required this.tie,
    required this.lose,
  });

  final String label;
  final int row; // 0..12, ace-high first
  final int col;
  final bool inRange;
  final int beat; // combo counts among this class that are in range
  final int tie;
  final int lose;

  CellStatus get status {
    if (!inRange) return CellStatus.out;
    if (beat + tie + lose == 0) return CellStatus.inRange; // no board yet
    if (beat > lose) return CellStatus.ahead;
    if (lose > beat) return CellStatus.behind;
    return CellStatus.split;
  }
}

/// The 13×13 starting-hand matrix (pairs on the diagonal, suited upper-right,
/// offsuit lower-left) — the visual of the opponents' range and where the hero
/// stands against each part of it.
@immutable
class HandGrid {
  const HandGrid(this.cells);

  /// 169 cells in row-major order (row = higher card, ace-first).
  final List<RangeCell> cells;
}

/// A full coaching read of the hero's current spot.
@immutable
class CoachReport {
  const CoachReport({
    required this.analysisAvailable,
    required this.spr,
    required this.stackBb,
    required this.potBb,
    required this.toCallBb,
    required this.potOdds,
    required this.equity,
    required this.madeHand,
    required this.opponents,
    required this.rangeRead,
    required this.breakdown,
    required this.handGrid,
    required this.polarized,
    required this.polarizedNote,
    required this.actionRead,
    required this.actions,
    required this.recommendedIndex,
    required this.recommendation,
  });

  /// False when it isn't the hero's turn — then only the stat block is meaningful.
  final bool analysisAvailable;

  // Raw stats.
  final double spr;
  final double stackBb;
  final double potBb;
  final double toCallBb;
  final double? potOdds; // equity needed to call; null when nothing to call
  final double equity; // 0..1, opponent-adjusted
  final String madeHand;
  final int opponents;

  // Range interpretation.
  final String rangeRead;
  final RangeBreakdown? breakdown; // postflop only
  final HandGrid? handGrid; // 13×13 range chart; null if the hero has no hand
  final bool polarized;
  final String? polarizedNote;

  final String actionRead;

  // Candidate actions + recommendation.
  final List<ActionEv> actions;
  final int recommendedIndex;
  final String recommendation;
}

/// Everything [HandCoach] needs, pulled from the table snapshot at the wiring
/// boundary so the use-case stays framework-free and testable.
@immutable
class HandCoachInput {
  const HandCoachInput({
    required this.hole,
    required this.board,
    required this.pot,
    required this.toCall,
    required this.heroCurrentBet,
    required this.currentBet,
    required this.effectiveStack,
    required this.bigBlind,
    required this.street,
    required this.raiseCount,
    required this.opponents,
    required this.opponentLabels,
    required this.canCheck,
    required this.canRaise,
    required this.minRaiseTo,
    required this.maxRaiseTo,
    this.random,
  });

  final List<Card> hole;
  final List<Card> board;
  final int pot;
  final int toCall;
  final int heroCurrentBet; // hero's chips in this street
  final int currentBet; // highest bet this street (villain's)
  final int effectiveStack; // min(hero, biggest live opponent)
  final int bigBlind;
  final BettingRound street;
  final int raiseCount; // 0 unraised, 1 open, 2 3-bet, 3+ 4-bet
  final int opponents; // live opponents (not folded, not hero)
  final List<String> opponentLabels; // names of live opponents (for the read)
  final bool canCheck;
  final bool canRaise;
  final int minRaiseTo;
  final int maxRaiseTo;
  final Random? random;
}

/// A directional in-hand coach. Reuses the same equity/range machinery the bots
/// use ([PostflopEquity], [HandRange]) so its read matches how the table plays,
/// then layers an EV model + a range breakdown on top. Estimates, not a solver.
class HandCoach {
  static const int _iterations = 600;
  static const double _rangeTop = 0.40;

  static CoachReport analyze(
    HandCoachInput i, {
    required bool analysisAvailable,
  }) {
    final rng = i.random ?? Random();
    final pot = i.pot;
    final bb = i.bigBlind <= 0 ? 1 : i.bigBlind;
    final toCall = i.toCall;
    final opp = max(1, i.opponents);

    // --- Raw stats ---
    final spr = pot <= 0 ? 0.0 : i.effectiveStack / pot;
    final potOdds = toCall <= 0 ? null : toCall / (pot + toCall);

    // --- Perceived range + equity (matches the bots' villain model) ---
    final dead = {...i.hole, ...i.board};
    final hasHand = i.hole.length == 2;
    final baseRange = HandRange.top(_rangeTop, dead: dead);
    final range =
        baseRange.narrowedBy(raiseCount: i.raiseCount, street: i.street);
    // Honest multiway share: hero must be best of all live opponents (a k-way
    // tie splits). This is correctly lower than heads-up equity but nothing
    // like the old equity^opponents, which crushed strong hands to nonsense
    // (AKo three-way read as ~18% instead of ~40%).
    double share(HandRange r) => PostflopEquity.equityMultiway(
          i.hole, i.board, r,
          opponents: opp, iterations: _iterations, random: rng,
        ).clamp(0.01, 0.99);
    final equity = hasHand ? share(range) : 0.5;
    // Equity against the range that keeps going once the hero puts in *more*
    // money, as a function of how many "raise steps" of pressure that continuing
    // range has absorbed. Memoized so each level's Monte-Carlo runs once. The
    // key correctness point: a bigger bet folds out more, so the *callers* are
    // stronger — a 100bb shove into a 4-chip pot is called only by the very top
    // of the range (AJo ~30%), never the whole top-20% (~57%). `_betEv` picks
    // the level from the bet's pot-fraction (see [_calledLevel]).
    final calledMemo = <int, double>{};
    double calledEquity(int level) => !hasHand
        ? 0.5
        : calledMemo.putIfAbsent(
            level,
            () => share(baseRange.narrowedBy(
                raiseCount: level, street: i.street)),
          );

    final madeHand = i.board.length >= 3 && hasHand
        ? HandEvaluator.evaluate([...i.hole, ...i.board]).rank.label
        : _preflopLabel(i.hole);

    // One pass over the perceived range builds both the beat/lose split and the
    // 13×13 chart (postflop grid is coloured by ahead/behind; preflop it just
    // shades the range).
    final analysis = hasHand ? _analyzeVsRange(i.hole, i.board, range) : null;
    final breakdown = analysis?.breakdown;
    final handGrid = analysis?.grid;

    // --- Polarization (facing a big turn/river bet ⇒ value-or-bluff range) ---
    final potBeforeBet = max(1, pot - toCall);
    final betFrac = toCall <= 0 ? 0.0 : toCall / potBeforeBet;
    final onLateStreet =
        i.street == BettingRound.turn || i.street == BettingRound.river;
    final polarized = toCall > 0 && onLateStreet && betFrac >= 0.66;

    final rangeRead = _rangeRead(i, range, dead, breakdown, opp);
    final polarizedNote =
        polarized ? _polarizedNote(potOdds, betFrac, breakdown) : null;
    final actionRead = _actionRead(i, betFrac);

    // --- Candidate action EVs ---
    final actions = analysisAvailable
        ? _actions(i, pot, equity, calledEquity, spr)
        : const <ActionEv>[];
    // (calledEquity is a size-aware function, resolved per bet inside _actions.)
    var best = 0;
    for (var k = 1; k < actions.length; k++) {
      if (actions[k].ev > actions[best].ev) best = k;
    }
    final recommendation = actions.isEmpty
        ? 'Analysis is available on your turn.'
        : _recommendation(actions[best], equity, potOdds, polarized);

    return CoachReport(
      analysisAvailable: analysisAvailable,
      spr: spr,
      stackBb: i.effectiveStack / bb,
      potBb: pot / bb,
      toCallBb: toCall / bb,
      potOdds: potOdds,
      equity: equity,
      madeHand: madeHand,
      opponents: i.opponents,
      rangeRead: rangeRead,
      breakdown: breakdown,
      handGrid: handGrid,
      polarized: polarized,
      polarizedNote: polarizedNote,
      actionRead: actionRead,
      actions: actions,
      recommendedIndex: actions.isEmpty ? -1 : best,
      recommendation: recommendation,
    );
  }

  // ---- Range breakdown: what we beat vs. lose to, right now ----------------

  static ({RangeBreakdown? breakdown, HandGrid grid}) _analyzeVsRange(
    List<Card> hole,
    List<Card> board,
    HandRange range,
  ) {
    final postflop = board.length >= 3;
    final hero = postflop ? HandEvaluator.evaluate([...hole, ...board]) : null;
    final dead = {...hole, ...board};

    // Per-cell tallies over the 13×13 grid, plus overall totals.
    final inR = List<bool>.filled(169, false);
    final beat = List<int>.filled(169, 0);
    final tie = List<int>.filled(169, 0);
    final lose = List<int>.filled(169, 0);
    var oBeat = 0, oTie = 0, oLose = 0;
    final beatRanks = <String>{};
    final loseRanks = <String>{};

    for (final c in range.combos) {
      if (dead.contains(c.$1) || dead.contains(c.$2)) continue;
      final idx = _cellIndex(c.$1, c.$2);
      inR[idx] = true;
      if (hero != null) {
        final villain = HandEvaluator.evaluate([c.$1, c.$2, ...board]);
        final cmp = hero.compareTo(villain);
        if (cmp > 0) {
          beat[idx]++;
          oBeat++;
          beatRanks.add(villain.rank.label);
        } else if (cmp < 0) {
          lose[idx]++;
          oLose++;
          loseRanks.add(villain.rank.label);
        } else {
          tie[idx]++;
          oTie++;
        }
      }
    }

    final labels = _gridLabels();
    final grid = HandGrid([
      for (var i = 0; i < 169; i++)
        RangeCell(
          label: labels[i],
          row: i ~/ 13,
          col: i % 13,
          inRange: inR[i],
          beat: beat[i],
          tie: tie[i],
          lose: lose[i],
        ),
    ]);

    RangeBreakdown? breakdown;
    if (hero != null) {
      final total = max(1, oBeat + oTie + oLose);
      breakdown = RangeBreakdown(
        combos: oBeat + oTie + oLose,
        beat: oBeat / total,
        tie: oTie / total,
        lose: oLose / total,
        beatClasses: _topClasses(beatRanks, ascending: false),
        loseClasses: _topClasses(loseRanks, ascending: true),
      );
    }
    return (breakdown: breakdown, grid: grid);
  }

  /// The row-major index (0..168) of the starting-hand cell for two cards:
  /// pairs on the diagonal, suited upper-right, offsuit lower-left, ace-first.
  static int _cellIndex(Card a, Card b) {
    final ia = 14 - a.rank.value;
    final ib = 14 - b.rank.value;
    if (a.rank == b.rank) return ia * 13 + ia;
    final hi = min(ia, ib);
    final lo = max(ia, ib);
    final suited = a.suit == b.suit;
    final r = suited ? hi : lo;
    final c = suited ? lo : hi;
    return r * 13 + c;
  }

  static const _gridRanks = ['A', 'K', 'Q', 'J', 'T', '9', '8', '7', '6', '5', '4', '3', '2'];

  static List<String> _gridLabels() => [
    for (var r = 0; r < 13; r++)
      for (var c = 0; c < 13; c++)
        if (r == c)
          '${_gridRanks[r]}${_gridRanks[r]}'
        else
          '${_gridRanks[min(r, c)]}${_gridRanks[max(r, c)]}${c > r ? 's' : 'o'}',
  ];

  /// Orders hand-class labels by strength; strongest-first for what we lose to,
  /// weakest-first for what we beat. Keeps a readable handful.
  static List<String> _topClasses(Set<String> labels, {required bool ascending}) {
    const order = [
      'High Card',
      'Pair',
      'Two Pair',
      'Three of a Kind',
      'Straight',
      'Flush',
      'Full House',
      'Four of a Kind',
      'Straight Flush',
    ];
    final list = labels.toList()
      ..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
    final ordered = ascending ? list : list.reversed.toList();
    return ordered.take(4).toList();
  }

  // ---- EV model ------------------------------------------------------------

  /// How many "raise steps" of pressure the continuing (calling) range has
  /// absorbed, given the hero already faces [raiseCount] raises and is now
  /// betting/raising [betFrac] of the pot. Bigger bets fold out more, so the
  /// callers left are stronger — this is what stops a huge overbet/shove from
  /// being scored against a loose range it would never actually get called by.
  static int _calledLevel(int raiseCount, double betFrac) {
    var level = raiseCount + 1; // continuing at all means beating our aggression
    if (betFrac >= 4) {
      level += 3; // overbet / shove into a small pot — only the nuts call
    } else if (betFrac >= 2) {
      level += 2;
    } else if (betFrac >= 1) {
      level += 1;
    }
    return level;
  }

  static List<ActionEv> _actions(
    HandCoachInput i,
    int pot,
    double equity,
    double Function(int level) calledEquity,
    double spr,
  ) {
    final out = <ActionEv>[];
    final toCall = i.toCall;

    if (toCall > 0) {
      out.add(const ActionEv(
        kind: CoachAction.fold,
        label: 'Fold',
        ev: 0,
        note: 'Forfeit the pot; risk nothing more.',
      ));
      final evCall = equity * pot - (1 - equity) * toCall;
      out.add(ActionEv(
        kind: CoachAction.call,
        label: 'Call',
        toAmount: toCall,
        ev: evCall,
        note: 'Win $pot w.p. ${_pct(equity)}, lose the call otherwise.',
      ));
    } else if (i.canCheck) {
      out.add(ActionEv(
        kind: CoachAction.check,
        label: 'Check',
        ev: equity * pot * 0.85,
        note: 'Realize your equity passively — no fold equity.',
      ));
    }

    // Bet / raise sizes as pot fractions (mirrors the action bar's sizing),
    // clamped to the legal range, de-duplicated after clamping.
    if (i.canRaise) {
      final fractions = toCall > 0
          ? const [(0.5, 'small'), (1.0, 'medium'), (1.5, 'big')]
          : const [(0.33, '⅓ pot'), (0.66, '⅔ pot'), (1.0, 'pot')];
      final seen = <int>{};
      final raising = toCall > 0;
      for (final (frac, tag) in fractions) {
        final to = (i.currentBet + pot * frac)
            .round()
            .clamp(i.minRaiseTo, i.maxRaiseTo);
        if (!seen.add(to)) continue; // clamped onto an existing size
        out.add(_betEv(i, pot, calledEquity, to, tag, raising));
      }
      // Add an explicit all-in when short or when it isn't already the top size.
      if (spr < 1.5 || !seen.contains(i.maxRaiseTo)) {
        if (seen.add(i.maxRaiseTo)) {
          out.add(_betEv(i, pot, calledEquity, i.maxRaiseTo, 'all-in', raising,
              allIn: true));
        }
      }
    }
    return out;
  }

  /// [calledEquity] maps a range-narrowing *level* to the hero's equity against
  /// the range that continues at that level. `_betEv` derives the level from the
  /// bet's pot-fraction (bigger bet ⇒ tighter callers ⇒ lower equity), so the
  /// "when called" branch is scored against the range that would actually call
  /// *this* size — not the wide pre-bet range.
  static ActionEv _betEv(
    HandCoachInput i,
    int pot,
    double Function(int level) calledEquity,
    int to,
    String tag,
    bool raising, {
    bool allIn = false,
  }) {
    final heroAdds = to - i.heroCurrentBet;
    final villainToCall = to - i.currentBet;
    final betFrac = pot <= 0 ? 1.0 : heroAdds / pot;
    // Base fold equity grows with bet size, but is capped by how committed the
    // opponents already are: each prior raise this street shrinks how often they
    // fold to more aggression. Betting into no raise can fold up to ~75%, but a
    // 5-bet shove over a 4-bet almost never gets through — so the ceiling drops
    // steeply. Without this the model credited a KTo shove vs a 4-bet with ~75%
    // fold equity and (wrongly) loved it.
    const foldCeiling = [0.75, 0.55, 0.32, 0.12, 0.08];
    final ceil = foldCeiling[i.raiseCount.clamp(0, foldCeiling.length - 1)];
    var fEq = (0.15 + 0.45 * betFrac).clamp(0.0, ceil);
    fEq = pow(fEq, max(1, i.opponents)).toDouble(); // all opponents must fold
    // Callers of *this* size are stronger the bigger we bet.
    final eqCalled = calledEquity(_calledLevel(i.raiseCount, betFrac));
    final calledPot = pot + heroAdds + villainToCall;
    final evCalled = eqCalled * calledPot - heroAdds;
    final ev = fEq * pot + (1 - fEq) * evCalled;
    return ActionEv(
      kind: raising ? CoachAction.raise : CoachAction.bet,
      label: allIn ? 'All-in' : (raising ? 'Raise to' : 'Bet'),
      toAmount: to,
      sizingTag: allIn ? 'all-in' : tag,
      ev: ev,
      note: 'Fold equity ~${_pct(fEq)}; when called, ${_pct(eqCalled)} of a '
          '$calledPot pot.',
    );
  }

  // ---- Narrative ------------------------------------------------------------

  static String _rangeRead(
    HandCoachInput i,
    HandRange range,
    Set<Card> dead,
    RangeBreakdown? b,
    int opp,
  ) {
    final who = i.opponentLabels.isEmpty
        ? '$opp opponent${opp == 1 ? '' : 's'}'
        : i.opponentLabels.join(', ');
    final allCombos = HandRange.all(dead: dead).length;
    final pct = allCombos == 0 ? 0 : (range.length / allCombos * 100).round();
    final aggression = switch (i.raiseCount) {
      >= 3 => 'a 4-bet+',
      2 => 'a 3-bet',
      1 => 'a raise',
      _ => 'no raise',
    };
    final head = '$who in the pot. After $aggression this street, their '
        'continuing range is roughly the top $pct% of hands.';
    if (b == null) return head;
    return '$head Right now you beat ${_pct(b.beat)} of it'
        '${b.loseClasses.isEmpty ? '' : ' and lose to ${_pct(b.lose)} '
            '(${b.loseClasses.join(', ')})'}.';
  }

  static String _polarizedNote(double? potOdds, double betFrac, RangeBreakdown? b) {
    final needed = potOdds == null ? '—' : _pct(potOdds);
    return 'Polarized spot: a big ${_x(betFrac)} bet reps strong value or a '
        'bluff, with little in between. This is a bluff-catch — the call turns '
        'on how often they are bluffing, not your exact strength. You need them '
        'bluffing ≥ $needed of the time to call profitably; against a polarized '
        'range every bluff-catcher you hold has the same value (all beat the '
        'bluffs, all lose to the value).';
  }

  static String _actionRead(HandCoachInput i, double betFrac) {
    if (i.toCall <= 0) {
      return i.canCheck
          ? 'Checked to you on the ${i.street.label.toLowerCase()}. You can '
              'check or take the betting lead.'
          : 'Your action on the ${i.street.label.toLowerCase()}.';
    }
    return 'Facing a ${_x(betFrac)} bet on the ${i.street.label.toLowerCase()} '
        '(${i.raiseCount >= 2 ? '${i.raiseCount}-bet pot' : 'single-raised'}).';
  }

  static String _recommendation(
    ActionEv best,
    double equity,
    double? potOdds,
    bool polarized,
  ) {
    final odds = potOdds == null ? null : _pct(potOdds);
    return switch (best.kind) {
      CoachAction.fold =>
        'Fold — ${_pct(equity)} equity can\'t cover the $odds pot odds'
            '${polarized ? ', and a polarized range gives no fold equity to bluff-raise' : ''}.',
      CoachAction.check =>
        'Check — realize your ${_pct(equity)} cheaply; not enough to bet for '
            'value or fold equity.',
      CoachAction.call => polarized
          ? 'Call — as a bluff-catcher your ${_pct(equity)} beats the $odds pot '
              'odds; you only need enough of their range to be bluffs.'
          : 'Call — ${_pct(equity)} beats the $odds pot odds.',
      CoachAction.bet || CoachAction.raise =>
        '${best.label} ${best.sizingTag} — highest-EV line: '
            '${_pct(equity)} equity plus fold equity make it best.',
    };
  }

  // ---- Helpers --------------------------------------------------------------

  static String _pct(double v) => '${(v * 100).round()}%';
  static String _x(double frac) {
    if (frac >= 0.9) return frac >= 1.4 ? 'overbet' : 'pot-sized';
    if (frac >= 0.55) return '⅔-pot';
    if (frac >= 0.4) return 'half-pot';
    return 'small';
  }

  static const _pairWords = {
    '2': 'twos',
    '3': 'threes',
    '4': 'fours',
    '5': 'fives',
    '6': 'sixes',
    '7': 'sevens',
    '8': 'eights',
    '9': 'nines',
    'T': 'tens',
    'J': 'jacks',
    'Q': 'queens',
    'K': 'kings',
    'A': 'aces',
  };

  static String _preflopLabel(List<Card> hole) {
    if (hole.length != 2) return '—';
    final a = hole[0], b = hole[1];
    if (a.rank == b.rank) return 'pocket ${_pairWords[a.rank.label]}';
    final hi = a.rank.value >= b.rank.value ? a : b;
    final lo = a.rank.value >= b.rank.value ? b : a;
    return '${hi.rank.label}${lo.rank.label}${a.suit == b.suit ? 's' : 'o'}';
  }
}
