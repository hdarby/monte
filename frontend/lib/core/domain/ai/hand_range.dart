import 'dart:math';

import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/core/domain/engine/hand_strength.dart';

/// A plausible set of two-card holdings a villain could have — the "range" a
/// player reasons about. Pure data; no engine mutation.
///
/// v1 is an unweighted set built by taking the strongest fraction of starting
/// hands (ranked by [HandStrength.preflopOf], the baked equity table), which
/// models "a villain of this tightness entered with these hands". Betting is
/// folded in by [narrowedBy], which tightens the set as the pot escalates.
/// Combo *weights* and board-filtered postflop ranges are future refinements.
class HandRange {
  /// Combos ordered strongest-first when built via [top]; order is irrelevant
  /// for equity but lets [narrowedBy] slice off the strongest fraction.
  const HandRange(this.combos);

  final List<(Card, Card)> combos;

  bool get isEmpty => combos.isEmpty;
  int get length => combos.length;

  /// Every two-card combo excluding [dead] (the hero's holes + the board).
  factory HandRange.all({Set<Card> dead = const {}}) =>
      HandRange(_combos(dead));

  /// The strongest [fraction] (in `(0,1]`) of all combos by preflop equity —
  /// i.e. a villain who continues with roughly the top `fraction` of hands.
  factory HandRange.top(double fraction, {Set<Card> dead = const {}}) {
    final all = _combos(dead)
      ..sort((a, b) => HandStrength.playabilityOf(b.$1, b.$2)
          .compareTo(HandStrength.playabilityOf(a.$1, a.$2)));
    final n = (all.length * fraction.clamp(0.0, 1.0)).round().clamp(1, all.length);
    return HandRange(all.sublist(0, n));
  }

  /// A tighter range reflecting shown aggression: each raise this street, each
  /// street past the flop, and — crucially — the *size* of the bet being faced
  /// trims the range toward its strongest hands. Assumes a ranked range (built
  /// via [top]).
  ///
  /// [betFraction] is the size of the bet being faced as a fraction of the pot
  /// (e.g. `1.0` == pot-sized, `3.0` == a 3×-pot overbet). Big bets are
  /// polarized/value-heavy, so the continuing range collapses toward premiums as
  /// they grow: a small bet (≤½ pot) is left alone, a pot-sized bet trims the
  /// range by a third, and overbets shrink it hard (2× ⇒ ×0.40, 3× ⇒ ×0.29).
  /// This is what stops a bot crediting a 3×-pot jam with the same wide range as
  /// a min-bet and then hero-calling it — the range (and hence the hero's equity)
  /// craters, so marginal hands fold on pot odds without any ad-hoc size clamp.
  HandRange narrowedBy({
    int raiseCount = 0,
    BettingRound? street,
    double betFraction = 0.0,
  }) {
    // Each bet/raise this street tightens the range hard (a villain who puts in
    // money is far stronger than their preflop continuing range).
    var factor = pow(0.5, max(0, raiseCount)).toDouble();
    // Mild, because `polarisedOn` now does the board-aware tightening. These
    // used to be the only thing narrowing a later-street range, so they were set
    // hard; leaving them there double-counts and over-folds the turn and river.
    if (street == BettingRound.turn) factor *= 0.92;
    if (street == BettingRound.river) factor *= 0.85;
    // Bet-size discipline: small sizings (≤½ pot) are unchanged, larger bets
    // reciprocally shrink the range — pot ⇒ ×0.67, 2× pot ⇒ ×0.40, 3× ⇒ ×0.29.
    if (betFraction > 0.5) factor *= 1.0 / (1.0 + (betFraction - 0.5));
    final n = (combos.length * factor).round().clamp(1, combos.length);
    return HandRange(combos.sublist(0, n));
  }

  /// The subset of this range a villain would actually **bet** on [board]:
  /// their strongest made hands (value) plus a tail of their weakest
  /// (air and draws), with the middling hands — the ones a real player checks
  /// back — removed.
  ///
  /// This corrects the single biggest hand-reading error in a pot-odds bot.
  /// [top] and [narrowedBy] rank combos by *preflop* strength only and never
  /// look at the board, so a "tight" river range stays dense with unpaired big
  /// cards that lose to any pair. A bluff-catcher then measures huge equity
  /// against it and calls on pot odds essentially forever. Filtering by made
  /// strength **on this board** makes a bluff-catcher's equity converge on the
  /// range's actual bluff share — which is the honest number a call has to beat.
  ///
  /// [bluffFraction] is the share of the betting range that is air/draws (the
  /// caller derives it from the bet size — see `ProfilePostflopPolicy`).
  ///
  /// [betRangeFraction] is how wide the represented betting range is. It is
  /// deliberately generous, and calibrated rather than derived: because the
  /// value slice is taken from the *top* of an already preflop-strong range, a
  /// narrow slice is effectively "villain always has the nuts" and a
  /// bluff-catcher folds every river. Widening it admits the thin value real
  /// players bet — hands a marginal holding actually beats. Measured over 400
  /// simulated hands, 0.85 puts fold-to-bet at roughly 47/52/56% on
  /// flop/turn/river, which is where real play sits; 0.55 pushed the river to
  /// 83%. Retune with `test/ai/postflop_discipline_test.dart`.
  ///
  /// Note the bottom slice is the right home for semibluffs too: on the flop and
  /// turn a flush draw evaluates as high-card, so it lands in the bluff tail
  /// naturally, without a separate draw model.
  HandRange polarisedOn(
    List<Card> board, {
    required double bluffFraction,
    double betRangeFraction = 0.85,
  }) {
    if (board.isEmpty || combos.length < 4) return this;
    // Score once per combo, then sort — evaluating inside the comparator would
    // cost O(n log n) seven-card evaluations on every decision.
    final scored = [
      for (final c in combos)
        (c, HandEvaluator.evaluate([c.$1, c.$2, ...board])),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final keep = (scored.length * betRangeFraction.clamp(0.1, 1.0))
        .round()
        .clamp(2, scored.length);
    final bluffs = (keep * bluffFraction.clamp(0.0, 1.0)).round().clamp(0, keep);
    final value = keep - bluffs;
    return HandRange([
      for (final s in scored.take(value)) s.$1,
      for (final s in scored.sublist(scored.length - bluffs)) s.$1,
    ]);
  }

  static List<(Card, Card)> _combos(Set<Card> dead) {
    final live = [
      for (final suit in Suit.values)
        for (final rank in Rank.values)
          if (!dead.contains(Card(rank, suit))) Card(rank, suit),
    ];
    final out = <(Card, Card)>[];
    for (var i = 0; i < live.length; i++) {
      for (var j = i + 1; j < live.length; j++) {
        out.add((live[i], live[j]));
      }
    }
    return out;
  }
}
