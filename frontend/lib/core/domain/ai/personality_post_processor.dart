import 'dart:math';

import 'package:monte/core/domain/ai/action_candidate.dart';

/// Owns the two personality-adjacent jobs that used to live inline in
/// `ProfilePostflopPolicy.decide()`, scattered across every return point:
///
/// 1. **Signature-move bookkeeping.** Deciding which named moves actually
///    *changed the decision* for the [ActionCandidate] that was chosen, and
///    firing them — never merely because a move's condition held (see
///    `characteristic_catalog.dart` / `trigger_observer.dart` for why that
///    distinction matters: a counter that ticks on every hand tells you
///    nothing).
/// 2. **Bounded close-decision mixing.** At a genuine two-live-candidate spot
///    (call vs. fold near `callBar`, bet vs. check near the value/bluff
///    thresholds), a hand sitting exactly on the bar is a coin-flip in real
///    poker, not a hard cutoff — a logistic pick keeps that honest without
///    ever flipping a decision that isn't actually close.
class PersonalityPostProcessor {
  PersonalityPostProcessor(Random random) : _random = random;

  final Random _random;

  /// The equity/threshold-scale margin at which two candidates are "close
  /// enough" to mix rather than hard-cutoff.
  ///
  /// `margin` here is a single noisy Monte-Carlo equity sample
  /// (`PostflopEquity.equityMultiway`, ~160 iterations), not a clean
  /// deterministic distance from the bar — so this can't be tuned purely off
  /// "how big a gap counts as close" the way `riverMargin` (0.02) or
  /// `stickyDelta` (up to -0.14) can. Started at 0.05, which measurably broke
  /// `signature_moves_test`'s `Sticky_Showdown` spot (a top-pair-worst-kicker
  /// hand deliberately chosen to sit *near* `callBar` for a disciplined fold):
  /// fold rate dropped from >0.9 to ~0.58, because per-trial MC sampling noise
  /// on `eq` is itself often >0.02–0.04 wide, so most trials' *noisy* gap
  /// looked "close" even though the hand's *true* equity sits comfortably
  /// below the bar. 0.01 is the largest value that leaves that gate (and
  /// `profile_calibration_test`, `postflop_discipline_test`,
  /// `deep_stack_discipline_test`) untouched while still catching genuine
  /// coin-flips — a hand whose single equity sample lands within 1 point of
  /// its own bar.
  static const double closeDecisionMargin = 0.01;

  /// The search-backed counterpart of [closeDecisionMargin]. `Postflop
  /// SearchEvaluator`'s candidate margins are `IsmctsEngine` mean-reward
  /// differences — hero net chips normalized to ~[-1, 1] by total chips in
  /// play (see `IsmctsEngine._heroPayoff`) — a different, larger-scale unit
  /// than the heuristic evaluator's equity-fraction margins, so reusing
  /// [closeDecisionMargin] here would either almost never fire (a chip-scale
  /// gap rarely lands under 0.01) or, if the scales happened to overlap by
  /// coincidence, would have been tuned for the wrong noise source (equity
  /// sampling noise vs. search variance across a fixed 500 iterations).
  /// Started at 0.02 — a similar order of magnitude to `closeDecisionMargin`
  /// but re-derived rather than copied — and verified against
  /// `signature_moves_test` forced onto the search backend: signature moves
  /// still fire at that value, so it was left there rather than narrowed
  /// further (the calibration tests don't run the search backend, since the
  /// cutover only ever activates at `tableCount <= 1`).
  static const double closeDecisionMarginSearch = 0.02;

  /// Bounded logistic mix between a [chosen] candidate and its nearest live
  /// alternative, when they are within [marginScale] of each other.
  ///
  /// [chosen] is what the evaluator's hard-cutoff logic picked; [runnerUp] is
  /// the next-best candidate at the same decision point (e.g. fold, when the
  /// evaluator picked call). If `runnerUp` is null, or the two aren't close,
  /// [chosen] is returned untouched — this only ever perturbs genuine
  /// coin-flips, never a hand that clearly wants one action.
  ///
  /// [marginScale] defaults to [closeDecisionMargin] (the heuristic
  /// evaluator's equity-fraction scale); pass [closeDecisionMarginSearch]
  /// when [chosen]/[runnerUp] came from `PostflopSearchEvaluator` instead.
  ///
  /// The mix probability is a logistic in the margin between the two
  /// candidates, saturating well before the bound so a "close" decision at
  /// the edge of the window still favours the hard-cutoff winner more often
  /// than not.
  ActionCandidate mix(
    ActionCandidate chosen,
    ActionCandidate? runnerUp, {
    double? marginScale,
  }) {
    if (runnerUp == null) return chosen;
    final scale = marginScale ?? closeDecisionMargin;
    final gap = (chosen.margin - runnerUp.margin).abs();
    if (gap >= scale) return chosen;
    // Logistic in the gap: at gap == 0 the two are 50/50; by
    // closeDecisionMargin the hard-cutoff winner is picked ~88% of the time.
    // Scale (k=40) is tuned so the curve reaches that saturation right at the
    // margin bound rather than well past it.
    const k = 40.0;
    final pChosen = 1.0 / (1.0 + exp(-k * gap));
    return _random.nextDouble() < pChosen ? chosen : runnerUp;
  }

  /// Fires every signature-move trigger the chosen [candidate] actually
  /// earned, via [fire]. Pure bookkeeping — it does not change what action is
  /// returned, only what gets recorded as having fired.
  void fireTriggers(ActionCandidate candidate, void Function(String) fire) {
    switch (candidate.label) {
      case 'floatTakeAway':
        fire('Float_And_Take_Away');
      case 'slowPlayTrap':
        fire('Slow_Play_Trap');
      case 'valueBet':
      case 'bluffBet':
        final pv = candidate.meta['pv'] as double? ?? 0.0;
        final geoBoost = candidate.meta['geoBoost'] as double? ?? 0.0;
        final sr = candidate.meta['sr'] as double? ?? 0.0;
        final tiltBlowupBluff =
            candidate.meta['tiltBlowupBluff'] as bool? ?? false;
        if (pv > 0) fire('Leverage_Pressure');
        if (geoBoost > 0) fire('Geometric_Overbet_Execution');
        if (sr > 0) fire('Soul_Read');
        if (tiltBlowupBluff) fire('Tilt_Blowup');
      case 'raise':
        final pv = candidate.meta['pv'] as double? ?? 0.0;
        final geoBoost = candidate.meta['geoBoost'] as double? ?? 0.0;
        final checkRaiseMerchant =
            candidate.meta['checkRaiseMerchant'] as bool? ?? false;
        if (pv > 0) fire('Leverage_Pressure');
        if (geoBoost > 0) fire('Geometric_Overbet_Execution');
        if (checkRaiseMerchant) fire('Check_Raise_Merchant');
      case 'call':
      case 'floatCall':
      case 'heroCall':
      case 'fold':
        _fireBarShiftTriggers(candidate, fire);
    }
  }

  /// Record only when a bar-shifting trait actually pushed `callBar` past
  /// this hand's real equity, in either direction — not every trait that
  /// happened to be authored on the profile. See `ProfilePostflopPolicy`'s
  /// original inline comment (now here) for the full rationale.
  void _fireBarShiftTriggers(
    ActionCandidate candidate,
    void Function(String) fire,
  ) {
    final callBar = candidate.meta['callBar'] as double?;
    final baseBar = candidate.meta['baseBar'] as double?;
    final eq = candidate.meta['eq'] as double?;
    if (callBar == null || baseBar == null || eq == null) return;
    final stickyDelta = candidate.meta['stickyDelta'] as double? ?? 0.0;
    final chaseDelta = candidate.meta['chaseDelta'] as double? ?? 0.0;
    final shutdownDelta = candidate.meta['shutdownDelta'] as double? ?? 0.0;
    final underbluffFires = candidate.meta['underbluffFires'] as bool? ?? false;

    if (callBar < baseBar && eq >= callBar && eq < baseBar) {
      if (stickyDelta < 0) fire('Sticky_Showdown');
      if (chaseDelta < 0) fire('Tilt_Chase');
    } else if (callBar > baseBar && eq < callBar && eq >= baseBar) {
      if (underbluffFires) fire('Underbluff_Exploit');
      if (shutdownDelta > 0) fire('Tilt_Shutdown');
    }
  }
}
