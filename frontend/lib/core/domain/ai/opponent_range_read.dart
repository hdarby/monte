import 'dart:math';

import 'package:meta/meta.dart';
import 'package:monte/core/domain/ai/hand_range.dart';
import 'package:monte/core/domain/ai/postflop_equity.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/core/domain/engine/hand_strength.dart';

/// Where the hero stands against a given opponent holding, from the hero's point
/// of view: [ahead] = the hero beats it (green), [behind] = the hero loses to it
/// (red), [split] = roughly a coin-flip (amber).
enum RangeStance { ahead, behind, split }

/// The opponent's table position, which tightens an unraised/opening range:
/// [early] (UTG) is tightest, [late] (cutoff/button) is widest, [blinds] play a
/// wide, capped range when they just call.
enum RangePosition { early, middle, late, blinds, unknown }

/// One starting-hand class in the 13×13 grid, read as part of an opponent's
/// likely holding: how *likely* they hold it ([weight]) and where the hero
/// stands against it ([stance]).
@immutable
class RangeReadCell {
  const RangeReadCell({
    required this.label,
    required this.row,
    required this.col,
    required this.weight,
    required this.combos,
    required this.heroEquity,
    required this.stance,
    required this.unlikelyPremium,
  });

  final String label;
  final int row; // 0..12, ace-first (pairs on the diagonal)
  final int col;

  /// Likelihood the opponent holds this class given their action, in [0,1].
  final double weight;

  /// Live combos of this class (after removing the hero's cards + the board).
  final int combos;

  /// Hero equity vs a representative combo of this class, in [0,1].
  final double heroEquity;
  final RangeStance stance;

  /// A super-premium (QQ+, AK) that the opponent's passive line makes unlikely —
  /// flagged so the UI can call it out even though the naive range would include
  /// it.
  final bool unlikelyPremium;

  bool get negligible => weight < 0.06;
}

/// The full read of an opponent's likely preflop hand range, conditioned on how
/// they've acted this hand, with each of the 169 starting-hand classes weighted
/// by likelihood and coloured by where the hero stands against it.
///
/// The headline behaviour: a passive line (limp / flat-call, no preflop raise)
/// makes **super-premium** holdings unlikely — a competent player raises QQ+/AK —
/// so those cells are down-weighted and flagged rather than shown as a live part
/// of the range just because they're "strong".
@immutable
class OpponentRangeRead {
  const OpponentRangeRead({required this.cells, required this.note});

  /// 169 cells in row-major order (row = higher card, ace-first).
  final List<RangeReadCell> cells;

  /// A one-line plain-language summary of the read.
  final String note;

  /// The heaviest cell weight, for normalising the display opacity.
  double get maxWeight =>
      cells.fold(0.0, (m, c) => c.weight > m ? c.weight : m);

  static final List<Rank> _ranksHiToLo = Rank.values.reversed.toList();

  /// Builds the read for an opponent given the hero's cards, the board, and the
  /// opponent's this-hand action summary (see `Player`/`SeatView`).
  static OpponentRangeRead estimate({
    required List<Card> heroHole,
    required List<Card> board,
    required bool vpip,
    required int preflopRaiseLevel,
    required bool raisedPostflop,
    RangePosition position = RangePosition.unknown,
    Random? random,
  }) {
    final rng = random ?? Random();
    final dead = {...heroHole, ...board};
    final riverPlus = board.length >= 5;

    final cells = <RangeReadCell>[];
    for (var row = 0; row < 13; row++) {
      for (var col = 0; col < 13; col++) {
        final hiIdx = min(row, col);
        final loIdx = max(row, col);
        final hi = _ranksHiToLo[hiIdx];
        final lo = _ranksHiToLo[loIdx];
        final pair = row == col;
        final suited = col > row;
        final label = pair
            ? '${hi.label}${hi.label}'
            : '${hi.label}${lo.label}${suited ? 's' : 'o'}';

        final combos = _combosOf(hi, lo, pair: pair, suited: suited, dead: dead);
        final s = HandStrength.preflopOf(
            Card(hi, Suit.spades), Card(lo, suited ? Suit.spades : Suit.hearts));
        final superPrem = _isSuperPremium(hi, lo, pair);

        var weight = _baseWeight(
          strength: s,
          vpip: vpip,
          preflopRaiseLevel: preflopRaiseLevel,
          position: position,
        );
        var unlikely = false;
        if (superPrem && preflopRaiseLevel == 0) {
          // A competent player raises QQ+/AK preflop; a limp/flat/free-check line
          // makes them unlikely (occasional trap, hence non-zero, not removed).
          weight *= 0.12;
          unlikely = true;
        }
        if (raisedPostflop && board.length >= 3 && combos.isNotEmpty) {
          weight *= _postflopPolarisation(combos.first, board);
        }
        weight = weight.clamp(0.0, 1.0);

        // Where the hero stands: equity vs a representative live combo.
        double heroEq = 0.5;
        var stance = RangeStance.split;
        if (combos.isNotEmpty) {
          heroEq = PostflopEquity.equity(
            heroHole,
            board,
            HandRange([combos.first]),
            iterations: riverPlus ? 1 : 120,
            random: rng,
          );
          stance = heroEq >= 0.55
              ? RangeStance.ahead
              : heroEq <= 0.45
                  ? RangeStance.behind
                  : RangeStance.split;
        }

        cells.add(RangeReadCell(
          label: label,
          row: row,
          col: col,
          weight: combos.isEmpty ? 0 : weight,
          combos: combos.length,
          heroEquity: heroEq,
          stance: stance,
          unlikelyPremium: unlikely,
        ));
      }
    }
    return OpponentRangeRead(
      cells: cells,
      note: _note(
          vpip: vpip,
          preflopRaiseLevel: preflopRaiseLevel,
          raisedPostflop: raisedPostflop,
          position: position),
    );
  }

  /// The likelihood weight for a class of preflop strength [strength] (0..1),
  /// shaped by the opponent's preflop line and position. Each step of preflop
  /// aggression (open → 3-bet → 4-bet) collapses the range harder toward
  /// premiums; earlier position tightens an open/limp.
  static double _baseWeight({
    required double strength,
    required bool vpip,
    required int preflopRaiseLevel,
    required RangePosition position,
  }) {
    // Earlier position → a tighter opening/limping range (higher cutoff).
    final posShift = switch (position) {
      RangePosition.early => 0.08,
      RangePosition.middle => 0.03,
      _ => 0.0,
    };
    if (preflopRaiseLevel >= 3) {
      return _logistic(strength, 0.83, 0.045); // 4-bet+: essentially QQ+/AK
    }
    if (preflopRaiseLevel == 2) {
      return _logistic(strength, 0.71, 0.05); // 3-bet: strong, premium-heavy
    }
    if (preflopRaiseLevel == 1) {
      return _logistic(strength, 0.58 + posShift, 0.06); // open-raise
    }
    if (vpip) {
      // Limped or flat-called: a playable but not premium-heavy range peaking on
      // speculative/medium hands; super-premiums are handled separately.
      return _logistic(strength, 0.46 + posShift, 0.085);
    }
    // Saw the flop for free (checked option / limped BB): almost any two cards,
    // with only a mild lean toward the better ones.
    return (0.5 + 0.30 * (strength - 0.5)).clamp(0.12, 0.85);
  }

  /// Postflop aggression polarises toward made value and live semi-bluffs (a
  /// flush/straight draw), away from medium one-pair and dead air.
  static double _postflopPolarisation((Card, Card) combo, List<Card> board) {
    final made =
        HandEvaluator.evaluate([combo.$1, combo.$2, ...board]).rank.index;
    if (made >= HandRank.twoPair.index) return 1.7; // value
    if (made == HandRank.pair.index) return 0.85; // thin
    return _hasStrongDraw(combo, board) ? 1.1 : 0.5; // semi-bluff vs dead air
  }

  /// A four-flush or open-ended straight draw using the two hole cards + board.
  static bool _hasStrongDraw((Card, Card) combo, List<Card> board) {
    final cards = [combo.$1, combo.$2, ...board];
    // Flush draw: four to a suit.
    for (final suit in Suit.values) {
      if (cards.where((c) => c.suit == suit).length == 4) return true;
    }
    // Open-ended straight draw: four consecutive ranks present (ace low or high).
    final vals = {for (final c in cards) c.rank.value};
    if (vals.contains(Rank.ace.value)) vals.add(1); // wheel
    for (var lo = 1; lo <= 11; lo++) {
      if (vals.contains(lo) &&
          vals.contains(lo + 1) &&
          vals.contains(lo + 2) &&
          vals.contains(lo + 3)) {
        return true;
      }
    }
    return false;
  }

  static double _logistic(double x, double mid, double k) =>
      1 / (1 + exp(-(x - mid) / k));

  static bool _isSuperPremium(Rank hi, Rank lo, bool pair) {
    if (pair) return hi.value >= Rank.queen.value; // QQ, KK, AA
    return hi == Rank.ace && lo == Rank.king; // AKs, AKo
  }

  static List<(Card, Card)> _combosOf(
    Rank hi,
    Rank lo, {
    required bool pair,
    required bool suited,
    required Set<Card> dead,
  }) {
    final out = <(Card, Card)>[];
    final suits = Suit.values;
    if (pair) {
      for (var i = 0; i < suits.length; i++) {
        for (var j = i + 1; j < suits.length; j++) {
          final a = Card(hi, suits[i]);
          final b = Card(hi, suits[j]);
          if (!dead.contains(a) && !dead.contains(b)) out.add((a, b));
        }
      }
    } else if (suited) {
      for (final s in suits) {
        final a = Card(hi, s);
        final b = Card(lo, s);
        if (!dead.contains(a) && !dead.contains(b)) out.add((a, b));
      }
    } else {
      for (final sa in suits) {
        for (final sb in suits) {
          if (sa == sb) continue;
          final a = Card(hi, sa);
          final b = Card(lo, sb);
          if (!dead.contains(a) && !dead.contains(b)) out.add((a, b));
        }
      }
    }
    return out;
  }

  static String _note({
    required bool vpip,
    required int preflopRaiseLevel,
    required bool raisedPostflop,
    required RangePosition position,
  }) {
    final pos = switch (position) {
      RangePosition.early => ' from early position',
      RangePosition.middle => ' from middle position',
      RangePosition.late => ' from late position',
      RangePosition.blinds => ' from the blinds',
      RangePosition.unknown => '',
    };
    final fired = raisedPostflop ? ' and fired postflop' : '';
    if (preflopRaiseLevel >= 3) {
      return '4-bet+ preflop$fired — the top of the range (QQ+, AK).';
    }
    if (preflopRaiseLevel == 2) {
      return '3-bet preflop$fired — a strong, premium-heavy range.';
    }
    if (preflopRaiseLevel == 1) {
      return 'Raised preflop$pos$fired — a strong opening range.';
    }
    if (vpip) {
      return 'Limped / flat-called preflop$pos — super-premiums (QQ+, AK) unlikely.';
    }
    return 'Saw the flop without raising$pos — nearly any two cards.';
  }
}
