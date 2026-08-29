import 'dart:math';

import 'package:monte/core/domain/ai/action_candidate.dart';
import 'package:monte/core/domain/ai/heuristic_postflop_evaluator.dart';
import 'package:monte/core/domain/ai/ismcts.dart';
import 'package:monte/core/domain/ai/mental_state.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/stack_context.dart';
import 'package:monte/core/domain/ai/trigger_context.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/board_texture.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

/// A search-backed drop-in replacement for [HeuristicPostflopEvaluator],
/// used only at the true final table (`tableCount <= 1`) where the field is
/// small enough to afford a real search per decision.
///
/// Takes the **identical** input set `ProfilePostflopPolicy.decide()` already
/// computes — `eq`, tilt/exploit terms, `TriggerContext` — so it plugs into
/// the same caller and the same `PersonalityPostProcessor` without either
/// having to know which evaluator ran. What changes is only *how* the action
/// is chosen: instead of equity-vs-threshold branches, a fixed-iteration
/// `IsmctsEngine` search picks the actual action, and `eq` (already computed,
/// not re-derived) is used purely to *classify* a bet/raise as value or bluff
/// for `PersonalityPostProcessor.fireTriggers` bookkeeping — the search
/// decides *whether and how big* to bet; the existing equity read decides
/// what to call that bet.
///
/// Candidate margins here are `IsmctsEngine` mean-reward differences, a
/// different scale from the heuristic evaluator's equity-fraction margins —
/// see `PersonalityPostProcessor.closeDecisionMarginSearch`.
///
/// The search's own pick is vetoed by [HeuristicPostflopEvaluator]'s
/// commitment gates (`commitOk`/`flushCommitOk`) before anything else runs —
/// see the comment at the veto site in [decide] for why.
class PostflopSearchEvaluator {
  /// [random] should be the policy's shared, seeded instance, matching every
  /// other evaluator/post-processor in `ProfilePostflopPolicy` — the search's
  /// own determinizer and rollouts draw from it, so reusing it keeps the
  /// whole decision seed-reproducible.
  ///
  /// [profile] is mapped to a [PersonalityProfile] (`PlayerProfile.
  /// toPersonalityProfile`) so the search's risk-utility payoff transform
  /// reflects *this* seat's actual tightness/risk tolerance — without it,
  /// every search-backed decision used `IsmctsEngine`'s
  /// `PersonalityProfile.balanced()` default regardless of whose seat it
  /// was, so a disciplined pro's search never valued a stack-off any
  /// differently than a maniac's would.
  PostflopSearchEvaluator(Random random, PlayerProfile profile)
      : _engine = IsmctsEngine(
          config: const IsmctsConfig(iterations: 500),
          random: random,
          profile: profile.toPersonalityProfile(),
        );

  final IsmctsEngine _engine;

  ({ActionCandidate chosen, ActionCandidate? runnerUp}) decide({
    required PokerGame game,
    required Player p,
    required PlayerProfile profile,
    required StackContext ctx,
    required TriggerContext tc,
    required MentalReads? mental,
    required double eq,
    required bool isDraw,
    required BoardTexture? texture,
    required double pv,
    required double sr,
    required double geoBoost,
    required double checkRaiseProf,
    required double exploit,
    required double sizeScale,
    required double deepFactor,
    required double rValueThin,
    required double rBluffMore,
    required double rSuspect,
    required int liveOpp,
    required int toCall,
    required int bb,
    required bool canRaise,
    required double betFraction,
    required bool inPosition,
  }) {
    final edges = _engine.evaluateEdges(game, p);
    if (edges.isEmpty) {
      // Defensive: the abstraction should never return an empty menu (the
      // passive action is always offered), but never leave a bot with
      // nothing to do.
      return (
        chosen: ActionCandidate(
          toCall == 0 ? const GameAction.check() : const GameAction.fold(),
          label: toCall == 0 ? 'check' : 'fold',
        ),
        runnerUp: null,
      );
    }

    var winner = edges.first;
    for (final e in edges) {
      if (e.visits > winner.visits ||
          (e.visits == winner.visits && e.meanReward > winner.meanReward)) {
        winner = e;
      }
    }

    // Discipline floor. The search has no equivalent to the heuristic
    // evaluator's commitment gates yet, and at 500 iterations with the
    // default `BotStrategy` rollout it calls off stacks far too liberally —
    // measured, not assumed: amateurs beating pros by 90-150+ bb/100 in
    // `amateur_strength_test`, a bust rate 2.6x the acceptable bound in
    // `deep_stack_discipline_test`. Veto a search-chosen call/bet/raise/
    // all-in that risks a large fraction of the stack unless `eq` (already
    // computed, not re-derived) clears the identical bar
    // `HeuristicPostflopEvaluator` uses for the same spot. A stopgap until
    // the search itself — more iterations, or a personality-aware rollout
    // opponent model instead of the generic `BotStrategy` — can be trusted
    // to reason its way to that discipline on its own; revisit rather than
    // treat this veto as the destination.
    final risked = switch (winner.action.type) {
      ActionType.call => toCall,
      ActionType.bet ||
      ActionType.raise ||
      ActionType.allIn =>
        winner.action.amount - p.currentBet,
      ActionType.check || ActionType.fold => 0,
    };
    final aggressive = winner.action.type == ActionType.bet ||
        winner.action.type == ActionType.raise ||
        winner.action.type == ActionType.allIn;
    final disciplined = HeuristicPostflopEvaluator.commitOk(
          p,
          risked,
          eq,
          deepFactor,
          aggressive: aggressive,
        ) &&
        HeuristicPostflopEvaluator.flushCommitOk(game, p, risked, eq);
    if (!disciplined) {
      return (
        chosen: ActionCandidate(
          toCall == 0 ? const GameAction.check() : const GameAction.fold(),
          label: toCall == 0 ? 'check' : 'fold',
        ),
        runnerUp: null,
      );
    }

    double meanOf(ActionType t) {
      for (final e in edges) {
        if (e.action.type == t) return e.meanReward;
      }
      return 0.0;
    }

    if (toCall == 0) {
      if (winner.action.type != ActionType.bet &&
          winner.action.type != ActionType.allIn) {
        return (
          chosen: ActionCandidate(winner.action, label: 'check'),
          runnerUp: null,
        );
      }
      final threshold = HeuristicPostflopEvaluator.valueThreshold(
        exploit: exploit,
        pv: pv,
        sr: sr,
        deepFactor: deepFactor,
        rValueThin: rValueThin,
      );
      final wantsValue = eq > threshold;
      final mood = mental?.stateFor(p.id);
      final tiltBlowupBluff = !wantsValue &&
          mood != null &&
          mood.isTilted &&
          profile.proficiencyOf('Tilt_Blowup') > 0;
      final checkMean = meanOf(ActionType.check);
      return (
        chosen: ActionCandidate(
          winner.action,
          label: wantsValue ? 'valueBet' : 'bluffBet',
          margin: winner.meanReward - checkMean,
          meta: {
            'pv': pv,
            'geoBoost': geoBoost,
            'sr': sr,
            'tiltBlowupBluff': tiltBlowupBluff,
          },
        ),
        runnerUp: ActionCandidate(const GameAction.check(), label: 'check'),
      );
    }

    // Facing a bet.
    final barInputs = HeuristicPostflopEvaluator.callBarMeta(
      game: game,
      p: p,
      profile: profile,
      tc: tc,
      mental: mental,
      deepFactor: deepFactor,
      betFraction: betFraction,
      toCall: toCall,
    );
    final barShiftMeta = {
      'callBar': barInputs.callBar,
      'baseBar': barInputs.baseBar,
      'eq': eq,
      'stickyDelta': barInputs.stickyDelta,
      'chaseDelta': barInputs.chaseDelta,
      'shutdownDelta': barInputs.shutdownDelta,
      'underbluffFires': barInputs.underbluffFires,
    };

    switch (winner.action.type) {
      case ActionType.fold:
        final callMean = meanOf(ActionType.call);
        return (
          chosen: ActionCandidate(
            winner.action,
            label: 'fold',
            margin: winner.meanReward - callMean,
            meta: barShiftMeta,
          ),
          runnerUp: ActionCandidate(
            const GameAction.call(),
            label: 'call',
            meta: barShiftMeta,
          ),
        );
      case ActionType.call:
        final foldMean = meanOf(ActionType.fold);
        return (
          chosen: ActionCandidate(
            winner.action,
            label: 'call',
            margin: winner.meanReward - foldMean,
            meta: barShiftMeta,
          ),
          runnerUp: ActionCandidate(
            const GameAction.fold(),
            label: 'fold',
            meta: barShiftMeta,
          ),
        );
      case ActionType.raise:
      case ActionType.allIn:
        final isCheckRaise = p.checkedThisRound;
        return (
          chosen: ActionCandidate(
            winner.action,
            label: 'raise',
            meta: {
              'pv': pv,
              'geoBoost': geoBoost,
              'checkRaiseMerchant': isCheckRaise && checkRaiseProf > 0,
            },
          ),
          runnerUp: null,
        );
      case ActionType.check:
      case ActionType.bet:
        // Not offered by the abstraction while facing a bet — unreachable,
        // but fall back to the raw action rather than throw.
        return (
          chosen: ActionCandidate(winner.action, label: 'call'),
          runnerUp: null,
        );
    }
  }
}
