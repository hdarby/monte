import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

/// Represents a single hand simulation result for a background table.
class HandSimulationResult {
  HandSimulationResult({
    required this.tableId,
    required this.busts,
    required this.stacks,
    required this.buttonIndex,
    required this.seedUsed,
  });

  final int tableId;

  /// Player id → starting stack for busted players
  final Map<String, int> busts;

  /// Updated chip stacks for all players at this table
  final Map<String, int> stacks;

  /// Next button position
  final int buttonIndex;

  /// The seed used (for debugging/verification)
  final int seedUsed;
}

/// Input data for a background table simulation. This must be serializable
/// across isolate boundaries.
class TableSimulationJob {
  TableSimulationJob({
    required this.tableId,
    required this.playerIds,
    required this.stacks,
    required this.currentButtonIndex,
    required this.seed,
    required this.handNumber,
    required this.smallBlind,
    required this.bigBlind,
    required this.ante,
    required this.chipUnit,
    required this.profiles, // profile id -> profile data
    required this.level,
  });

  final int tableId;
  final List<String> playerIds;
  final Map<String, int> stacks;
  final int currentButtonIndex;
  final int seed;
  final int handNumber;
  final int smallBlind;
  final int bigBlind;
  final int ante;
  final int chipUnit;
  final Map<String, PlayerProfile> profiles;
  final int level;
}

/// Manages a pool of isolates for parallel background table simulation.
class BackgroundTableSimulator {
  BackgroundTableSimulator({int poolSize = 4}) : _poolSize = poolSize;

  final int _poolSize;
  final List<SendPort> _sendPorts = [];
  final List<ReceivePort> _receivePorts = [];
  bool _initialized = false;

  /// Initialize the isolate pool
  Future<void> initialize() async {
    if (_initialized) return;

    for (var i = 0; i < _poolSize; i++) {
      final receivePort = ReceivePort();
      await Isolate.spawn(_isolateEntryPoint, receivePort.sendPort);
      final sendPort = await receivePort.first as SendPort;
      _sendPorts.add(sendPort);
      _receivePorts.add(receivePort);
    }

    _initialized = true;
  }

  /// Simulate a batch of hands from different tables in parallel
  Future<List<HandSimulationResult>> simulateBatch(
    List<TableSimulationJob> jobs,
  ) async {
    if (!_initialized) {
      throw StateError('BackgroundTableSimulator not initialized. Call initialize() first.');
    }

    if (jobs.isEmpty) return [];

    // Distribute jobs round-robin across isolates
    final futures = <Future<HandSimulationResult>>[];
    for (var i = 0; i < jobs.length; i++) {
      final isolateIndex = i % _poolSize;
      final receivePort = ReceivePort();

      _sendPorts[isolateIndex].send((jobs[i], receivePort.sendPort));
      futures.add(
        receivePort.first.then((dynamic result) {
          if (result is String) {
            // Error message
            throw Exception('Isolate error: $result');
          }
          return result as HandSimulationResult;
        }),
      );
    }

    return Future.wait(futures);
  }

  /// Cleanup isolates
  void dispose() {
    for (final port in _receivePorts) {
      port.close();
    }
    _sendPorts.clear();
    _receivePorts.clear();
    _initialized = false;
  }

  /// Static entry point for isolate
  static void _isolateEntryPoint(SendPort parentSendPort) {
    final receivePort = ReceivePort();
    parentSendPort.send(receivePort.sendPort);

    receivePort.listen((dynamic message) {
      if (message is! List || message.length != 2) return;

      final job = message[0] as TableSimulationJob;
      final responsePort = message[1] as SendPort;

      try {
        final result = _playHandInIsolate(job);
        responsePort.send(result);
      } catch (e) {
        responsePort.send('Error: $e');
      }
    });
  }

  /// Simulate a single hand in an isolate. Pure function with no side effects.
  static HandSimulationResult _playHandInIsolate(TableSimulationJob job) {
    // Create engine players from the job data
    final enginePlayers = <Player>[];
    for (final playerId in job.playerIds) {
      enginePlayers.add(
        Player(
          id: playerId,
          name: playerId,
          stack: job.stacks[playerId] ?? 0,
        ),
      );
    }

    // Create and play the game
    final game = PokerGame(
      players: enginePlayers,
      smallBlind: job.smallBlind,
      bigBlind: job.bigBlind,
      ante: job.ante,
      chipUnit: job.chipUnit,
      deck: Deck(random: Random(job.seed)),
    )..buttonIndex = job.currentButtonIndex;

    game.startHand();

    if (!game.isHandOver) {
      // Play through the hand using simple heuristic decisions
      while (!game.isHandOver) {
        final cur = game.currentPlayer;
        if (cur == null) break;

        // For background tables, use a lightweight decision policy
        // This is a placeholder - in the real implementation, you'd use
        // the appropriate policy from the profile
        final action = _makeSimpleDecision(game, cur);
        game.applyAction(action);
      }
    }

    // Collect results
    final stacks = <String, int>{};
    final busts = <String, int>{};
    final preBustStacks = <String, int>{};

    for (final p in enginePlayers) {
      stacks[p.id] = p.stack;
      if (p.stack == 0 && job.stacks[p.id]! > 0) {
        preBustStacks[p.id] = job.stacks[p.id]!;
        busts[p.id] = preBustStacks[p.id]!;
      }
    }

    return HandSimulationResult(
      tableId: job.tableId,
      busts: busts,
      stacks: stacks,
      buttonIndex: game.buttonIndex,
      seedUsed: job.seed,
    );
  }

  /// Simple lightweight decision for background table players
  static GameAction _makeSimpleDecision(PokerGame game, Player player) {
    final toCall = game.callAmount(player);

    if (toCall == 0) {
      return const GameAction.check();
    }

    // Simple heuristic: fold if we need to put in more than 10% of our stack
    if (toCall > player.stack * 0.1) {
      return const GameAction.fold();
    }

    return const GameAction.call();
  }
}
