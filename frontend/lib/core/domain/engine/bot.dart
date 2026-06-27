import 'dart:math';

import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_strength.dart';
import 'package:monte/core/domain/engine/player.dart';

/// A lightweight heuristic opponent.
///
/// Not a serious solver — it estimates hand strength (preflop heuristics,
/// postflop via the real evaluator), folds weak hands facing bets, calls
/// medium ones, and raises strong ones, with a dash of randomness so it isn't
/// fully predictable.
class BotStrategy implements DecisionPolicy {
  BotStrategy({Random? random}) : _random = random ?? Random();

  final Random _random;

  @override
  GameAction decide(PokerGame game, Player p) {
    final strength = HandStrength.estimate(game, p);
    final toCall = game.callAmount(p);
    final aggression = 0.9 + _random.nextDouble() * 0.3; // 0.9–1.2

    // No bet to face: check, or bet for value/bluff when strong.
    if (toCall == 0) {
      if (strength * aggression > 0.62 && p.stack > game.bigBlind) {
        final size = (game.pot * 0.6).round().clamp(game.bigBlind, p.stack);
        return GameAction.bet(p.currentBet + size);
      }
      return const GameAction.check();
    }

    // Facing a bet: weigh strength against pot odds.
    final potOdds = toCall / (game.pot + toCall);
    final adjusted = strength * aggression;

    if (adjusted > 0.8 && p.stack > toCall) {
      final raiseTo = game.minRaiseTo(p) + (game.pot * 0.5).round();
      return GameAction.raise(
        raiseTo.clamp(game.minRaiseTo(p), game.maxRaiseTo(p)),
      );
    }
    if (adjusted > potOdds || toCall <= game.bigBlind) {
      return const GameAction.call();
    }
    return const GameAction.fold();
  }
}
