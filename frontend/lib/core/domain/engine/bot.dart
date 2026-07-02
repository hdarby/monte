import 'dart:math';

import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/bet_snap.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_strength.dart';
import 'package:monte/core/domain/engine/player.dart';

/// A lightweight heuristic opponent.
///
/// Not a serious solver, but a believable tight-aggressive one: it estimates
/// hand strength (preflop heuristics, postflop via the real evaluator), folds
/// weak holdings, and prefers raising its playable hands to limping. A dash of
/// randomness keeps it from being fully predictable.
class BotStrategy implements DecisionPolicy {
  BotStrategy({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// Minimum preflop hand strength to voluntarily put money in. Folding below
  /// this keeps VPIP sane (~a top-quarter range) instead of playing everything.
  static const _preflopEntry = 0.50;

  @override
  GameAction decide(PokerGame game, Player p) {
    final strength = HandStrength.estimate(game, p);
    final toCall = game.callAmount(p);
    final bb = game.bigBlind;
    final aggression = 0.9 + _random.nextDouble() * 0.3; // 0.9–1.2
    final adjusted = strength * aggression;

    GameAction raiseBy(double potFraction) {
      final raw = game.minRaiseTo(p) + (game.pot * potFraction).round();
      final raiseTo =
          snapBet(raw, smallBlind: game.smallBlind, bigBlind: game.bigBlind)
              .clamp(game.minRaiseTo(p), game.maxRaiseTo(p));
      return GameAction.raise(raiseTo);
    }

    final potOdds = toCall / (game.pot + toCall);
    final raises = game.raiseCountThisRound;

    if (game.board.isEmpty) {
      // ----- Preflop: tight, raise-first-in, and tighten as bets escalate -----
      // Big blind with no raise to face: raise premiums, else take the free flop.
      if (toCall == 0) {
        return adjusted > 0.78 && p.stack > bb
            ? raiseBy(0.5)
            : const GameAction.check();
      }
      // Don't pay to enter with junk — this is what keeps VPIP reasonable.
      if (strength < _preflopEntry) return const GameAction.fold();

      // Facing a 3-bet or more: only premiums keep raising; otherwise call a
      // strong hand at a fair price, else fold. Stops the all-in raise wars.
      if (raises >= 2) {
        if (adjusted > 0.95 && p.stack > toCall) return raiseBy(0.6);
        if (strength >= 0.62 && adjusted > potOdds) return const GameAction.call();
        return const GameAction.fold();
      }
      // Unraised pot: open-raise rather than limp.
      if (raises == 0 && toCall <= bb && p.stack > toCall) return raiseBy(0.5);
      // Facing a single open: 3-bet premiums, else continue at a price.
      if (raises == 1 && adjusted > 0.85 && p.stack > toCall) return raiseBy(0.6);
      return adjusted > potOdds
          ? const GameAction.call()
          : const GameAction.fold();
    }

    // ----- Postflop: bet/raise strong, continue on pot odds -----
    if (toCall == 0) {
      if (adjusted > 0.62 && p.stack > bb) {
        final raw = p.currentBet + (game.pot * 0.6).round();
        final to = snapBet(raw, smallBlind: game.smallBlind, bigBlind: bb)
            .clamp(p.currentBet + bb, p.currentBet + p.stack);
        return GameAction.bet(to);
      }
      return const GameAction.check();
    }
    // Raise strong hands; once the pot's already been raised this street, only
    // a premium re-raises (don't escalate to all-in with one pair).
    final raiseBar = raises >= 2 ? 0.9 : 0.8;
    if (adjusted > raiseBar && p.stack > toCall) return raiseBy(0.5);
    if (adjusted > potOdds || toCall <= bb) return const GameAction.call();
    return const GameAction.fold();
  }
}
