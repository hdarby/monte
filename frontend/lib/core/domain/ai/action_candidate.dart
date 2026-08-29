import 'package:monte/core/domain/engine/actions.dart';

/// A single decision the heuristic postflop evaluator considered, plus enough
/// context for a post-processor (personality/tilt shading, close-decision
/// mixing) to reason about it without re-deriving the poker judgement.
///
/// [margin] is signed distance the candidate cleared its own bar by, on the
/// same equity/threshold scale used throughout `ProfilePostflopPolicy` (e.g.
/// `equity - callBar`, or `eq - wantsValue bar`). A small `|margin|` marks a
/// genuinely close decision — the only place bounded mixing is worth doing;
/// a hand nowhere near its bar should never flip on a coin.
///
/// [onChosen] is fired only if this candidate is the one actually returned —
/// signature-move bookkeeping must record "this changed the decision", not
/// "the condition merely held".
class ActionCandidate {
  ActionCandidate(
    this.action, {
    this.label = '',
    this.margin = 0.0,
    this.meta = const {},
  });

  final GameAction action;

  /// Human-readable tag for debugging/tests (e.g. `'call'`, `'fold'`,
  /// `'valueBet'`, `'bluff'`). Also what `PersonalityPostProcessor` switches
  /// on to decide which signature-move triggers are even in play for this
  /// candidate.
  final String label;

  final double margin;

  /// Raw values the evaluator already computed that a post-processor needs to
  /// decide *whether a move actually changed the decision* (e.g. `callBar`
  /// before/after a tilt/read shift) — kept as plain data rather than a
  /// baked-in closure so that bookkeeping lives in one place
  /// (`PersonalityPostProcessor`), not scattered across every return point of
  /// the evaluator.
  final Map<String, Object?> meta;
}
