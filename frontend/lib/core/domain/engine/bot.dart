import 'dart:math';

import 'package:poker_client/core/domain/engine/actions.dart';
import 'package:poker_client/core/domain/engine/game.dart';
import 'package:poker_client/core/domain/engine/hand_evaluator.dart';
import 'package:poker_client/core/domain/engine/player.dart';

/// A lightweight heuristic opponent.
///
/// Not a serious solver — it estimates hand strength (preflop heuristics,
/// postflop via the real evaluator), folds weak hands facing bets, calls
/// medium ones, and raises strong ones, with a dash of randomness so it isn't
/// fully predictable.
class BotStrategy {
  BotStrategy({Random? random}) : _random = random ?? Random();

  final Random _random;

  GameAction decide(PokerGame game, Player p) {
    final strength = _strength(game, p);
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
      return GameAction.raise(raiseTo.clamp(game.minRaiseTo(p), game.maxRaiseTo(p)));
    }
    if (adjusted > potOdds || toCall <= game.bigBlind) {
      return const GameAction.call();
    }
    return const GameAction.fold();
  }

  /// Rough hand strength in [0, 1].
  double _strength(PokerGame game, Player p) {
    if (game.board.isEmpty) return _preflopStrength(p);

    final value = HandEvaluator.evaluate([...p.hole, ...game.board]);
    // Map made-hand category to a base strength, nudged by top card.
    final base = value.rank.index / (HandRank.values.length - 1);
    final kicker = (value.tiebreakers.first) / 14.0 * 0.05;
    return (base * 0.9 + kicker + 0.05).clamp(0.0, 1.0);
  }

  double _preflopStrength(Player p) {
    final a = p.hole[0].rank.value;
    final b = p.hole[1].rank.value;
    final high = max(a, b);
    final low = min(a, b);
    final suited = p.hole[0].suit == p.hole[1].suit;
    final gap = high - low;

    var s = (high + low) / 28.0 * 0.6;
    if (a == b) s += 0.35 + a / 28.0; // pocket pair
    if (suited) s += 0.08;
    if (gap == 1) s += 0.05; // connected
    if (high == 14) s += 0.05; // ace
    return s.clamp(0.0, 1.0);
  }
}
