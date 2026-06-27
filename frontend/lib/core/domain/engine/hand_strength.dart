import 'dart:math';

import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/core/domain/engine/player.dart';

/// A rough estimate of a player's hand strength in [0, 1], shared by the
/// heuristic and personality policies so they agree on "how good is this hand".
///
/// Preflop uses simple high-card/pair/suited/connected heuristics; postflop maps
/// the made-hand category (nudged by the top kicker) onto the same scale.
class HandStrength {
  const HandStrength._();

  static double estimate(PokerGame game, Player p) {
    if (game.board.isEmpty) return preflop(p);

    final value = HandEvaluator.evaluate([...p.hole, ...game.board]);
    final base = value.rank.index / (HandRank.values.length - 1);
    final kicker = value.tiebreakers.first / 14.0 * 0.05;
    return (base * 0.9 + kicker + 0.05).clamp(0.0, 1.0);
  }

  static double preflop(Player p) {
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
