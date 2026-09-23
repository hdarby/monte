part of 'local_game_repository.dart';

/// The bot-turn driving loop, split out of [LocalGameRepository] because it's
/// the one piece that has to reason about pacing/async (the others are all
/// synchronous state transitions).
extension LocalGameRepositoryBots on LocalGameRepository {
  /// Lets bots act with a short delay until it's the human's turn or the hand
  /// ends. In all-bots mode there's no human, so it plays the whole hand out;
  /// the next hand is dealt via [LocalGameRepository.startNextHand] (or
  /// batched via [LocalGameRepository.simulate]).
  Future<void> _runBots() async {
    if (_botsRunning) return;
    _botsRunning = true;
    try {
      final game = _game!;
      final budget = config.botThinkTime;
      while (!game.isHandOver) {
        final current = game.currentPlayer;
        if (current == null) break; // showdown / run-out resolves internally
        if (current.isHuman) break;

        final decider = _deciderFor(current);
        final sw = Stopwatch()..start();
        // An MCTS seat spends the pace budget on a deeper (cooperative-async)
        // search; every other brain decides instantly.
        final GameAction action;
        if (budget > Duration.zero && decider is IsmctsEngine) {
          action = await decider.decideTimed(game, current, budget: budget);
        } else {
          action = decider.decide(game, current);
        }
        if (_disposed) return;
        // Pad instant brains (or a search that finished early) up to the pace so
        // decisions feel uniformly timed regardless of the seat's brain.
        final remaining = budget - sw.elapsed;
        if (remaining > Duration.zero) {
          await Future<void>.delayed(remaining);
          if (_disposed) return;
        }
        _applyAndRecord(current, action);
        _publish();
      }
    } finally {
      _botsRunning = false;
    }
  }
}
