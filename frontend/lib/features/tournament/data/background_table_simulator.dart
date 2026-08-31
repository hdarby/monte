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
///
/// Background tables run completely independently:
/// - Each table has its own hand counter and seed
/// - Simulation paces itself based on the player's table speed
/// - Supports pause/resume (especially for hand-for-hand)
class BackgroundTableSimulator {
  BackgroundTableSimulator({int poolSize = 4}) : _poolSize = poolSize;

  final int _poolSize;
  final List<SendPort> _sendPorts = [];
  final List<ReceivePort> _receivePorts = [];
  bool _initialized = false;

  /// User-initiated pause (via UI button)
  bool _userPaused = false;

  /// Automatic pause due to hand-for-hand
  bool _handForHandPaused = false;

  /// Automatic pause while the level recap dialog is on screen
  bool _recapPaused = false;

  /// Automatic pause while the standings snapshot is being computed/rendered,
  /// so a background table can't mutate stacks mid-read.
  bool _renderPaused = false;

  /// Automatic pause once the player's own hand has been open too long
  /// without an action — they've likely stepped away, and the field
  /// shouldn't keep blazing through blind levels and background hands
  /// unattended in the meantime.
  bool _awayPaused = false;

  /// Moving average of hand durations at the player's table (milliseconds)
  double _averageHandDurationMs = 5000.0; // Start with 5 second estimate
  static const _movingAverageFactor = 0.3; // Exponential moving average smoothing

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

  /// User-initiated pause via UI button
  void pause() {
    _userPaused = true;
  }

  /// User-initiated resume via UI button
  void resume() {
    _userPaused = false;
  }

  /// Automatic pause due to hand-for-hand (all tables sync at same hand count)
  void pauseForHandForHand() {
    _handForHandPaused = true;
  }

  /// Automatic resume after hand-for-hand ends
  void resumeAfterHandForHand() {
    _handForHandPaused = false;
  }

  /// Automatic pause while the level recap dialog is on screen
  void pauseForRecap() {
    _recapPaused = true;
  }

  /// Automatic resume once the recap dialog closes
  void resumeAfterRecap() {
    _recapPaused = false;
  }

  /// Automatic pause while a standings snapshot is being read
  void pauseForRender() {
    _renderPaused = true;
  }

  /// Automatic resume once the standings snapshot has been read
  void resumeAfterRender() {
    _renderPaused = false;
  }

  /// Automatic pause once the player's hand has been open too long
  void pauseForAway() {
    _awayPaused = true;
  }

  /// Automatic resume once the player acts (or a new hand starts)
  void resumeFromAway() {
    _awayPaused = false;
  }

  /// Check if simulation is paused (user, hand-for-hand, recap dialog, a
  /// standings read in progress, or the player appears to have stepped away)
  bool get isPaused =>
      _userPaused ||
      _handForHandPaused ||
      _recapPaused ||
      _renderPaused ||
      _awayPaused;

  /// Check if user explicitly paused (not hand-for-hand pause)
  bool get isUserPaused => _userPaused;

  /// Update the moving average of hand duration (milliseconds).
  /// Called after each player table hand completes.
  void updateHandDuration(int durationMs) {
    _averageHandDurationMs =
        _averageHandDurationMs * (1 - _movingAverageFactor) +
        durationMs * _movingAverageFactor;
  }

  /// Get the current average hand duration estimate (milliseconds)
  double get averageHandDurationMs => _averageHandDurationMs;

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
