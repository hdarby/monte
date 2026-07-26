import 'package:monte/core/domain/ai/push_fold_chart.dart';
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
  });

  final DecisionPolicy _inner;
  final TournamentContext Function(PokerGame, Player) _contextFor;
  final PushFoldChart _chart;

  static const double _pushFoldMax = 12;
  static const double _tightenAt = 1.08;

  @override
  GameAction decide(PokerGame game, Player p) {
    final ctx = _contextFor(game, p);
    if (game.board.isEmpty && ctx.stackInBb <= _pushFoldMax) {
      return _chart.decide(game, p, ctx);
    }
    final action = _inner.decide(game, p);
    if (ctx.bubbleFactor >= _tightenAt) return _bubbleTighten(game, p, action, ctx);
    return action;
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
