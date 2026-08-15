import 'dart:math';

import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/push_fold_chart.dart';
import 'package:monte/core/domain/ai/trigger_observer.dart';
import 'package:monte/core/domain/ai/tournament_context.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_strength.dart';
import 'package:monte/core/domain/engine/player.dart';

/// Wraps any [DecisionPolicy] with tournament awareness, without rewriting the
/// underlying brain:
///
/// 1. **Short-stack push/fold** — below ~[_pushFoldMax] big blinds, preflop play
///    collapses to jam-or-fold via [PushFoldChart].
/// 2. **Bubble discipline** — near the money (bubble factor above [_tightenAt]),
///    a big call that risks a large chunk of stack is demoted to a fold unless
///    the hand clears a bar that rises with the ICM pressure.
///
/// The [TournamentContext] is supplied per decision by the controller (which
/// knows every table's stacks + the payouts). With the neutral cash context it's
/// a pass-through, so the same decider works in cash games too.
class IcmAdjustedDecider implements DecisionPolicy {
  IcmAdjustedDecider(
    this._inner,
    this._contextFor, {
    this._chart = const PushFoldChart(),
    this.profile,
    this.triggers,
    Random? random,
  }) : _random = random ?? Random();

  final DecisionPolicy _inner;
  final TournamentContext Function(PokerGame, Player) _contextFor;
  final PushFoldChart _chart;

  /// The seat's personality, for signature moves that only make sense with the
  /// tournament context to hand (see `Bubble_Predator`). Null for a plain seat.
  final PlayerProfile? profile;
  /// Records signature moves when they fire (see [TriggerObserver]).
  final TriggerObserver? triggers;
  final Random _random;

  static const double _pushFoldMax = 12;
  static const double _tightenAt = 1.08;

  @override
  GameAction decide(PokerGame game, Player p) {
    final ctx = _contextFor(game, p);
    if (game.board.isEmpty && ctx.stackInBb <= _pushFoldMax) {
      return _chart.decide(game, p, ctx);
    }
    final action = _inner.decide(game, p);

    // Bubble predator: the mirror image of bubble tightening. ICM makes
    // *everyone else* risk-averse near a pay jump, which makes their folding
    // range enormous -- so the player with this move attacks instead of
    // shrinking. Turns a fold or a check into a raise when the pot is unopened
    // and the opponents are the ones who cannot afford to call.
    final predator = profile?.proficiencyOf('Bubble_Predator') ?? 0.0;
    if (predator > 0 &&
        game.board.isEmpty &&
        ctx.bubbleFactor >= _tightenAt &&
        game.raiseCountThisRound == 0 &&
        (action.type == ActionType.fold || action.type == ActionType.check) &&
        p.stack > game.bigBlind * 8 &&
        _random.nextDouble() < 0.35 * predator * (ctx.bubbleFactor - 1).clamp(0.0, 1.0)) {
      final to = game.minRaiseTo(p);
      if (to <= game.maxRaiseTo(p) && to > p.currentBet) {
        triggers?.onFired('Bubble_Predator', p.id);
        return GameAction.raise(to);
      }
    }

    if (ctx.bubbleFactor >= _tightenAt) return _bubbleTighten(game, p, action, ctx);
    // Large-field bubble / in-the-money laddering, where exact ICM isn't run:
    // a stack-scaled survival premium demotes marginal stack-offs so a short/mid
    // stack doesn't bust when there's pay-jump value in simply surviving.
    if (ctx.ladderPressure >= 0.15) return _ladderTighten(game, p, action, ctx);
    return action;
  }

  /// Refuses to commit a large chunk of a laddering stack without a real hand:
  /// folds big calls, and abandons weak jams/raises (check if possible, else
  /// fold). Bar and trigger scale with [TournamentContext.ladderPressure].
  GameAction _ladderTighten(
      PokerGame game, Player p, GameAction action, TournamentContext ctx) {
    final toCall = game.callAmount(p);
    final int risked;
    switch (action.type) {
      case ActionType.call:
        if (toCall == 0) return action;
        risked = toCall;
      case ActionType.allIn:
        risked = p.stack;
      case ActionType.bet:
      case ActionType.raise:
        risked = (action.amount - p.currentBet).clamp(0, p.stack);
      case ActionType.fold:
      case ActionType.check:
        return action;
    }
    final commitFrac = risked / (p.stack + p.currentBet).clamp(1, 1 << 30);
    final trigger = (0.35 - 0.20 * ctx.ladderPressure).clamp(0.15, 0.35);
    if (commitFrac < trigger) return action; // a small commitment is fine
    final bar = (0.58 + 0.30 * ctx.ladderPressure).clamp(0.5, 0.90);
    final strength = game.board.isEmpty
        ? HandStrength.preflop(p)
        : HandStrength.estimate(game, p);
    if (strength >= bar) return action;
    if (toCall > 0) return const GameAction.fold();
    return game.canCheck(p) ? const GameAction.check() : const GameAction.fold();
  }

  /// Near the bubble, refuse to call off a large chunk of stack without a strong
  /// hand — the "don't bust on the bubble" adjustment. Only demotes big *calls*;
  /// betting/raising and small calls pass through.
  GameAction _bubbleTighten(
      PokerGame game, Player p, GameAction action, TournamentContext ctx) {
    if (action.type != ActionType.call) return action;
    final toCall = game.callAmount(p);
    if (toCall == 0) return action;
    final commitFrac = toCall / (p.stack + toCall);
    if (commitFrac < 0.4) return action; // a small call is fine

    final bar = (0.62 + 0.06 * (ctx.bubbleFactor - 1)).clamp(0.5, 0.92);
    final strength = game.board.isEmpty
        ? HandStrength.preflop(p)
        : HandStrength.estimate(game, p);
    return strength >= bar ? action : const GameAction.fold();
  }
}
