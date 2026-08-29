import 'dart:math';

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

    // Pot-odds floor. `Icm.bubbleFactor` legitimately caps at 5.0 (a real,
    // intentional ceiling — see `icm.dart`), and at that ceiling `bubbleAdj`
    // alone pins `cutoff` near its own 0.9 max — reachable by essentially
    // only AA, regardless of how cheap the call actually is. This chart has
    // no other concept of bet size: it was built for "should I shove my
    // whole stack," not "an opponent already committed a small fraction of
    // my stack, is calling trivially profitable." Without this floor, a
    // maxed-out bubble factor makes a short-stacked opponent's covering
    // stack fold to everything but a premium pair forever — an observed,
    // real stall that can run for hundreds of thousands of hands once the
    // field is down to a lopsided heads-up (confirmed: the identical
    // scenario, replayed without this floor, pinned `cutoff` at 0.9 for a
    // stack over 6x its opponent's and hit the 200k-hand safety net in half
    // of a 10-seed sweep). ICM pressure still tightens *marginal* decisions
    // (a modest margin over breakeven, scaled by how far the flat cutoff
    // sits above a coin flip) — it just can't manufacture an uncallable
    // bar out of a bet that pure pot odds already make an easy call.
    // Only when actually facing a bet — with nothing to call, this is a
    // shove-or-check-it-free decision, not a priced call, so the flat
    // ICM-tightened cutoff is the right (and only) bar either way.
    var requiredEquity = cutoff;
    if (toCall > 0) {
      final potOdds = toCall / (game.pot + toCall);
      final icmMargin = (cutoff - 0.5).clamp(0.0, 0.4) * 0.5;
      requiredEquity = min(cutoff, potOdds + icmMargin).clamp(0.0, 0.98);
    }

    if (s >= requiredEquity) {
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
