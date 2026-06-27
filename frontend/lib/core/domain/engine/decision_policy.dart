import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

/// A strategy that, given the current game and the player to act, returns a
/// legal action. The common seam for every kind of bot — heuristic, personality
/// policy, or search engine — so they're interchangeable.
abstract interface class DecisionPolicy {
  GameAction decide(PokerGame game, Player player);
}
