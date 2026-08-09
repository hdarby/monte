import 'dart:math';

import 'package:meta/meta.dart';

import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/game.dart';

/// The value types the in-hand coach produces and consumes: the scored actions,
/// the range breakdown and grid, the report the UI renders, and the input the
/// engine is handed. The analysis itself lives in `hand_coach.dart`.

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
