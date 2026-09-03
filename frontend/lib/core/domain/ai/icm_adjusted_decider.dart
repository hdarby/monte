import 'dart:math';

import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/push_fold_chart.dart';
import 'package:monte/core/domain/ai/trigger_observer.dart';
import 'package:monte/core/domain/ai/tournament_context.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/bet_sizing.dart';
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
/// 3. **Survival-pressure size damping** — every real tournament hand (not just
///    near the bubble) shrinks bets/raises toward the legal minimum, because
///    busting is permanent in a way a cash buy-in never is. See
///    [_survivalPressure]: this is the piece that's active at 300 BB on hand
///    one of a Main Event, where [ladderPressure]/[bubbleFactor] are both
///    exactly zero and nothing else in this class does anything at all.
/// 4. **A universal garbage-call trim** — a small, skill-*independent* chance
///    to fold a genuinely weak call instead of making it, gated by
///    [icmDiscipline] being irrelevant to it (see below).
///
/// [icmDiscipline] splits (1), (2) and the `Bubble_Predator` move from (3)/(4):
/// misplaying the *ICM math* — push/fold charts, bubble folding discipline — is
/// a skill gap a pro should have and a recreational player should not, so
/// `TournamentController` passes `icmDiscipline: false` for amateur seats. But
/// "I shouldn't call raises with any two cards as often when busting ends my
/// tournament" isn't ICM math, it's survival instinct — even bad players have
/// some of it — so (3) and (4) apply to every wrapped seat regardless of the
/// flag.
///
/// The [TournamentContext] is supplied per decision by the controller (which
/// knows every table's stacks + the payouts). With the neutral cash context
/// ([TournamentContext.cash]) every piece here is a no-op, so the same decider
/// works in cash games too.
class IcmAdjustedDecider implements DecisionPolicy {
  IcmAdjustedDecider(
    this._inner,
    this._contextFor, {
    this._chart = const PushFoldChart(),
    this.profile,
    this.triggers,
    this.icmDiscipline = true,
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

  /// Whether this seat gets the ICM-*math* pieces: push/fold charts, bubble/
  /// ladder folding discipline, and `Bubble_Predator`. `false` for amateur
  /// seats — see the class doc. Survival-pressure size damping and the
  /// garbage-call trim apply either way.
  final bool icmDiscipline;
  final Random _random;

  static const double _pushFoldMax = 12;
  static const double _tightenAt = 1.08;

  @override
  GameAction decide(PokerGame game, Player p) {
    final ctx = _contextFor(game, p);
    if (icmDiscipline && game.board.isEmpty && ctx.stackInBb <= _pushFoldMax) {
      return _chart.decide(game, p, ctx);
    }
    var action = _inner.decide(game, p);

    // Bubble predator: the mirror image of bubble tightening. ICM makes
    // *everyone else* risk-averse near a pay jump, which makes their folding
    // range enormous -- so the player with this move attacks instead of
    // shrinking. Turns a fold or a check into a raise when the pot is unopened
    // and the opponents are the ones who cannot afford to call.
    final predator = icmDiscipline ? profile?.proficiencyOf('Bubble_Predator') ?? 0.0 : 0.0;
    if (predator > 0 &&
        game.board.isEmpty &&
        ctx.bubbleFactor >= _tightenAt &&
        game.raiseCountThisRound == 0 &&
        (action.type == ActionType.fold || action.type == ActionType.check) &&
        p.stack > game.bigBlind * 8 &&
        _random.nextDouble() < 0.35 * predator * (ctx.bubbleFactor - 1).clamp(0.0, 1.0)) {
      final to = game.minRaiseTo(p);
      if (to <= game.maxRaiseTo(p) && to > p.currentBet) {
        triggers?.onFired('Bubble_Predator', p.id, game.round);
        return GameAction.raise(to);
      }
    }

    if (icmDiscipline) {
      if (ctx.bubbleFactor >= _tightenAt) {
        action = _bubbleTighten(game, p, action, ctx);
      } else {
        // Large-field bubble / in-the-money laddering, where exact ICM isn't
        // run: a stack-scaled survival premium demotes marginal stack-offs so
        // a short/mid stack doesn't bust when there's pay-jump value in simply
        // surviving.
        //
        // Ramped rather than gated on a flat `ladderPressure >= 0.15` cutoff —
        // that snapped the whole tighten on the instant a large field crossed
        // the line, so betting went from completely unconstrained to fully
        // laddered in a single hand. Below 0.15 the tighten now still fires,
        // just with a probability that rises linearly with ladderPressure, so
        // constraint eases in over the approach to the bubble instead of
        // flipping on. At and above 0.15 this always fires, exactly as before.
        final ramp = (ctx.ladderPressure / 0.15).clamp(0.0, 1.0);
        if (ramp > 0 && _random.nextDouble() < ramp) {
          action = _ladderTighten(game, p, action, ctx);
        }
      }
    }

    action = _trimGarbageCall(game, p, action, ctx);
    return _dampSize(game, p, action, _survivalPressure(ctx));
  }

  /// A continuous survival premium in `[0, 0.75]`, active on **every**
  /// tournament hand — 0 only for [TournamentContext.cash] (`playersLeft <= 0`).
  ///
  /// The `0.18` baseline is deliberately not derived from [ladderPressure] or
  /// [bubbleFactor]: both are exactly zero far from the money in a large field
  /// (see `TournamentController._ladderPressure`), which is precisely the 300
  /// BB / level-1 spot the baseline exists for. "This bust is permanent" is
  /// true from hand one, not just near the bubble — [ladderPressure]/
  /// [bubbleFactor] only sharpen the pressure further as the money approaches.
  ///
  /// A first-pass, reasoned constant rather than a measured one, in the same
  /// spirit as `OpenRanges.tableFactor`'s "a first stab, deliberately" — the
  /// tournament-vs-cash sizing test is what makes it checkable going forward.
  double _survivalPressure(TournamentContext ctx) {
    if (ctx.playersLeft <= 0) return 0; // the cash sentinel: no tournament
    final pressure = 0.18 +
        0.4 * ctx.ladderPressure +
        0.15 * (ctx.bubbleFactor - 1).clamp(0.0, 2.0);
    return pressure.clamp(0.0, 0.75);
  }

  /// Shrinks a surviving bet/raise toward the smallest legal size by
  /// [pressure], leaving the action type and every other action untouched.
  ///
  /// Never touches [ActionType.allIn] — a jam is a deliberate full commitment
  /// already gated by the inner policy's own stack-off thresholds, and must not
  /// be silently resized into something smaller than the hand's owner decided.
  GameAction _dampSize(
      PokerGame game, Player p, GameAction action, double pressure) {
    if (pressure <= 0) return action;
    final int floor;
    switch (action.type) {
      case ActionType.bet:
        floor = p.currentBet + game.bigBlind;
      case ActionType.raise:
        floor = game.minRaiseTo(p);
      case ActionType.allIn:
      case ActionType.call:
      case ActionType.fold:
      case ActionType.check:
        return action;
    }
    if (action.amount <= floor) return action;
    final to = (floor + (action.amount - floor) * (1 - pressure)).round();
    return action.type == ActionType.bet
        ? GameAction.bet(snapRaiseTo(game, p, to))
        : GameAction.raise(snapRaiseTo(game, p, to));
  }

  /// A small, skill-*independent* chance to fold a genuinely weak call instead
  /// of making it — see the class doc's point (4).
  ///
  /// Deliberately narrow: only calls (never the marginal-but-defensible ones
  /// that make a station or a chaser who they are — [_weakBar] is well below
  /// any hand a real player would call with a straight face), and only a
  /// *chance* scaled by [_survivalPressure], so garbage calls still happen —
  /// less relentlessly, not never. A hard cutoff here would be a nit-fest, not
  /// a discipline fix.
  static const _weakBar = 0.30;

  GameAction _trimGarbageCall(
      PokerGame game, Player p, GameAction action, TournamentContext ctx) {
    if (action.type != ActionType.call) return action;
    final pressure = _survivalPressure(ctx);
    if (pressure <= 0) return action;
    final toCall = game.callAmount(p);
    if (toCall == 0) return action; // a free check, not a call worth trimming
    final strength = game.board.isEmpty
        ? HandStrength.preflop(p)
        : HandStrength.estimate(game, p);
    if (strength >= _weakBar) return action;
    if (_random.nextDouble() >= 0.5 * pressure) return action;
    return const GameAction.fold();
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
