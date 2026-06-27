import 'dart:async';

import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/core/domain/engine/player.dart';
import 'package:monte/core/domain/hand_history.dart';
import 'package:monte/features/table/domain/game_repository.dart';
import 'package:monte/features/table/domain/table_snapshot.dart';

/// Static table configuration for a client-only game.
class TableConfig {
  const TableConfig({
    this.humanName = 'You',
    this.playerCount = 4,
    this.startingStack = 1000,
    this.smallBlind = 5,
    this.bigBlind = 10,
    this.allBots = false,
    this.botThinkTime = const Duration(milliseconds: 700),
    this.botType = BotType.heuristic,
    this.personality = const PersonalityProfile.balanced(),
    this.mctsIterations = 250,
    this.deckBuilder,
  });

  /// Total seats including the human. 2 = heads-up, up to 10 for a full table.
  final int playerCount;

  /// When true, every seat is a bot (evaluation mode, no human).
  final bool allBots;

  final String humanName;
  final int startingStack;
  final int smallBlind;
  final int bigBlind;
  final Duration botThinkTime;

  /// Which brain the bots use, and the personality shaping it.
  final BotType botType;
  final PersonalityProfile personality;

  /// Search budget per decision for [BotType.mcts].
  final int mctsIterations;

  /// Optional deck source — supply a seeded or [Deck.stacked] deck for
  /// reproducible games and tests. Defaults to a fresh shuffled deck.
  final Deck Function()? deckBuilder;

  /// Smallest and largest supported table sizes.
  static const int minPlayers = 2;
  static const int maxPlayers = 10;

  /// Names assigned to bots, in seat order (enough for a full table).
  static const List<String> botNamePool = [
    'Ada',
    'Boris',
    'Chen',
    'Dora',
    'Eli',
    'Farah',
    'Gus',
    'Hana',
    'Ivan',
    'Jo',
  ];

  int get botCount => allBots ? playerCount : playerCount - 1;
}

/// Client-only implementation: the entire game runs on-device. Bots act
/// automatically with a short delay so the table feels alive. In all-bots mode
/// the engine plays itself, recording every hand for analysis.
class LocalGameRepository extends GameRepository {
  LocalGameRepository({this.config = const TableConfig()});

  final TableConfig config;

  /// One decider per bot seat (keyed by player id), so seats can hold distinct
  /// personalities and a busted seat can be replaced independently.
  final Map<String, DecisionPolicy> _deciders = {};

  PokerGame? _game;
  bool _botsRunning = false;
  bool _disposed = false;

  final List<HandHistory> _history = [];
  int _handCounter = 0;
  List<HandPlayer> _recPlayers = [];
  List<ActionRecord> _recActions = [];

  final StreamController<TableSnapshot> _controller =
      StreamController<TableSnapshot>.broadcast();

  TableSnapshot _snapshot = TableSnapshot.empty;

  @override
  TableSnapshot get snapshot => _snapshot;

  @override
  Stream<TableSnapshot> watch() => _controller.stream;

  @override
  bool get isAllBots => config.allBots;

  @override
  List<HandHistory> get history => List.unmodifiable(_history);

  @override
  void clearHistory() {
    _history.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    if (!_controller.isClosed) _controller.close();
  }

  /// Builds a fresh table (players + engine) without dealing a hand.
  void _createGame() {
    final players = <Player>[
      if (!config.allBots)
        Player(
          id: 'human',
          name: config.humanName,
          stack: config.startingStack,
          isHuman: true,
        ),
      for (var i = 0; i < config.botCount; i++)
        Player(
          id: 'bot_$i',
          name: TableConfig.botNamePool[i % TableConfig.botNamePool.length],
          stack: config.startingStack,
        ),
    ];
    _game = PokerGame(
      players: players,
      smallBlind: config.smallBlind,
      bigBlind: config.bigBlind,
      deck: config.deckBuilder?.call(),
    );

    // A decider per bot seat, all starting from the configured personality.
    _deciders.clear();
    for (final p in players) {
      if (!p.isHuman) {
        _deciders[p.id] = buildDecider(
          config.botType,
          profile: config.personality,
          mctsIterations: config.mctsIterations,
        );
      }
    }
  }

  @override
  Future<void> newGame() async {
    _createGame();
    await startNextHand();
  }

  @override
  Future<void> startNextHand() async {
    if (_game == null) {
      await newGame();
      return;
    }
    _beginHand();
    _publish();
    await _runBots();
  }

  @override
  Future<void> submitAction(GameAction action) async {
    final game = _game;
    if (game == null) return;
    final current = game.currentPlayer;
    if (current == null || !current.isHuman) return;

    _applyAndRecord(current, action);
    _publish();
    await _runBots();
  }

  @override
  Future<void> simulate(int hands) async {
    if (_game == null) _createGame();
    final game = _game!;
    for (var h = 0; h < hands; h++) {
      if (_disposed) break;
      _beginHand();
      if (game.isHandOver) break; // not enough funded players
      while (!game.isHandOver) {
        final current = game.currentPlayer;
        if (current == null) break;
        _applyAndRecord(current, _deciderFor(current).decide(game, current));
      }
    }
    _publish();
  }

  // ---- Player management ----------------------------------------------------

  DecisionPolicy _deciderFor(Player p) => _deciders[p.id] ??= buildDecider(
    config.botType,
    profile: config.personality,
    mctsIterations: config.mctsIterations,
  );

  Player? _playerById(String id) {
    for (final p in _game?.players ?? const <Player>[]) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  void reloadPlayer(String id) {
    final p = _playerById(id);
    if (p == null) return;
    p.stack = config.startingStack;
    _publish();
  }

  @override
  void replacePlayer(String id, PersonalityArchetype archetype) {
    final p = _playerById(id);
    if (p == null) return;
    p.stack = config.startingStack;
    if (!p.isHuman) {
      p.name = _freshBotName();
      _deciders[id] = buildDecider(
        config.botType,
        profile: archetype.profile,
        mctsIterations: config.mctsIterations,
      );
    }
    _publish();
  }

  /// Picks a bot name not currently seated, falling back to a numbered guest.
  String _freshBotName() {
    final taken = {for (final p in _game?.players ?? const <Player>[]) p.name};
    for (final name in TableConfig.botNamePool) {
      if (!taken.contains(name)) return name;
    }
    return 'Guest $_handCounter';
  }

  /// Lets bots act with a short delay until it's the human's turn or the hand
  /// ends. In all-bots mode there's no human, so it plays the whole hand out;
  /// the next hand is dealt via [startNextHand] (or batched via [simulate]).
  Future<void> _runBots() async {
    if (_botsRunning) return;
    _botsRunning = true;
    try {
      final game = _game!;
      while (!game.isHandOver) {
        final current = game.currentPlayer;
        if (current == null) break; // showdown / run-out resolves internally
        if (current.isHuman) break;

        await Future<void>.delayed(config.botThinkTime);
        if (_disposed) return;
        _applyAndRecord(current, _deciderFor(current).decide(game, current));
        _publish();
      }
    } finally {
      _botsRunning = false;
    }
  }

  // ---- Recording ------------------------------------------------------------

  /// Deals a fresh hand and starts a new history record. In evaluation mode
  /// stacks are topped back up so every hand is full and independent.
  void _beginHand() {
    final game = _game!;
    if (config.allBots) {
      for (final p in game.players) {
        p.stack = config.startingStack;
      }
    }

    game.startHand();
    _handCounter++;
    _recActions = [];
    _recPlayers = [
      for (final p in game.players)
        if (p.hole.length == 2)
          HandPlayer(
            id: p.id,
            name: p.name,
            startingStack: p.stack + p.totalContributed, // pre-blind stack
            holeCards: p.hole.map((c) => c.code).toList(),
            isButton: game.players.indexOf(p) == game.buttonIndex,
          ),
    ];

    if (game.isHandOver) _finalizeHand(); // e.g. not enough players
  }

  void _applyAndRecord(Player player, GameAction action) {
    final game = _game!;
    final street = game.round;
    final callBefore = game.callAmount(player);

    game.applyAction(action);

    final int amount;
    switch (action.type) {
      case ActionType.bet:
      case ActionType.raise:
        amount = action.amount;
      case ActionType.call:
        amount = callBefore;
      case ActionType.allIn:
        amount = player.currentBet;
      case ActionType.fold:
      case ActionType.check:
        amount = 0;
    }

    _recActions.add(
      ActionRecord(
        playerId: player.id,
        street: street,
        type: action.type,
        amount: amount,
        potAfter: game.pot,
      ),
    );

    if (game.isHandOver) _finalizeHand();
  }

  void _finalizeHand() {
    final game = _game!;
    if (_recPlayers.isEmpty) return;

    _history.add(
      HandHistory(
        handNumber: _handCounter,
        smallBlind: game.smallBlind,
        bigBlind: game.bigBlind,
        players: _recPlayers,
        actions: _recActions,
        board: game.board.map((c) => c.code).toList(),
        results: [
          for (final r in game.results)
            HandResultRecord(
              playerId: r.player.id,
              amountWon: r.amountWon,
              handRank: r.handValue?.rank.label,
            ),
        ],
        finalStacks: {for (final p in _recPlayers) p.id: _stackOf(p.id)},
      ),
    );
    _recPlayers = [];
    _recActions = [];
  }

  int _stackOf(String id) => _game!.players.firstWhere((p) => p.id == id).stack;

  // ---- Snapshot -------------------------------------------------------------

  void _publish() {
    _snapshot = _buildSnapshot();
    if (!_controller.isClosed) _controller.add(_snapshot);
  }

  TableSnapshot _buildSnapshot() {
    final game = _game!;
    final showdownHappened = game.results.any((r) => r.handValue != null);
    final wonByPlayer = {for (final r in game.results) r.player: r.amountWon};
    final current = game.currentPlayer;

    final seats = <SeatView>[];
    for (var i = 0; i < game.players.length; i++) {
      final p = game.players[i];
      // In all-bots mode there's no human to protect, so reveal everyone.
      final reveal =
          p.isHuman || config.allBots || (showdownHappened && p.inHand);
      String? label;
      if (reveal && p.inHand && game.board.length == 5 && p.hole.length == 2) {
        label = HandEvaluator.evaluate([...p.hole, ...game.board]).rank.label;
      }
      seats.add(
        SeatView(
          id: p.id,
          name: p.name,
          isHuman: p.isHuman,
          stack: p.stack,
          currentBet: p.currentBet,
          folded: p.hasFolded,
          allIn: p.isAllIn,
          isButton: i == game.buttonIndex,
          isCurrent: current != null && current.id == p.id,
          holeCards: reveal ? List.of(p.hole) : null,
          handLabel: label,
          wonAmount: wonByPlayer[p] ?? 0,
        ),
      );
    }

    ActionContext? ctx;
    if (current != null && current.isHuman) {
      ctx = ActionContext(
        callAmount: game.callAmount(current),
        canCheck: game.canCheck(current),
        minRaiseTo: game.minRaiseTo(current),
        maxRaiseTo: game.maxRaiseTo(current),
        bigBlind: game.bigBlind,
        currentBet: game.currentBet,
      );
    }

    // Between hands in human-vs-bots play, flag anyone left with no chips so
    // the player can reload them or seat a fresh opponent. (All-bots mode tops
    // stacks up each hand, so no one busts there.)
    final busted = <String>[];
    if (!config.allBots && game.isHandOver) {
      for (final p in game.players) {
        if (p.stack == 0) busted.add(p.id);
      }
    }

    return TableSnapshot(
      seats: seats,
      board: List.of(game.board),
      pot: game.pot,
      round: game.round,
      currentPlayerId: current?.id,
      isHandOver: game.isHandOver,
      handInProgress: !game.isHandOver,
      log: List.of(game.log),
      actionContext: ctx,
      bustedPlayerIds: busted,
    );
  }
}
