import 'package:monte/core/domain/ai/tournament_context.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_strength.dart';
import 'package:monte/core/domain/engine/player.dart';

/// A short-stack **preflop shove-or-fold** policy — the dominant dynamic once a
/// tournament stack drops to ~a dozen big blinds, where post-flop play is moot
/// and the only real decisions are jam or fold.
///
/// The jam range widens as the stack shortens (desperation) and tightens as the
/// bubble factor rises (ICM pressure). It's a believable Nash-flavoured heuristic
/// keyed off the baked [HandStrength.preflop] table, not a solved chart.
class PushFoldChart {
  const PushFoldChart();

  GameAction decide(PokerGame game, Player p, TournamentContext ctx) {
    final s = HandStrength.preflop(p);
    final toCall = game.callAmount(p);

    // Shorter stack ⇒ lower cutoff (wider jam); higher bubble factor ⇒ higher
    // cutoff (tighter). Centered so ~12bb, chip-neutral opens the top ~half.
    final stackAdj = (12 - ctx.stackInBb).clamp(0.0, 12.0) * 0.02;
    final bubbleAdj = (ctx.bubbleFactor - 1) * 0.15;
    final cutoff = (0.52 - stackAdj + bubbleAdj).clamp(0.18, 0.9);

    if (s >= cutoff) {
      final canJam =
          p.stack > toCall && game.maxRaiseTo(p) >= game.minRaiseTo(p);
      // Jam all-in, or call off an existing all-in we can't full-raise.
      return canJam
          ? GameAction.raise(game.maxRaiseTo(p))
          : const GameAction.call();
    }
    // Below the jam range: take a free flop in the big blind, else fold.
    return toCall == 0 ? const GameAction.check() : const GameAction.fold();
  }
}
