import 'dart:async';

import '../engine/actions.dart';
import '../engine/bot.dart';
import '../engine/game.dart';
import '../engine/hand_evaluator.dart';
import '../engine/player.dart';
import 'game_repository.dart';
import 'table_snapshot.dart';

/// Static table configuration for a client-only game.
class TableConfig {
  const TableConfig({
    this.humanName = 'You',
    this.playerCount = 4,
    this.startingStack = 1000,
    this.smallBlind = 5,
    this.bigBlind = 10,
    this.botThinkTime = const Duration(milliseconds: 700),
  });

  /// Total seats including the human. 2 = heads-up, up to 10 for a full table.
  final int playerCount;

  final String humanName;
  final int startingStack;
  final int smallBlind;
  final int bigBlind;
  final Duration botThinkTime;

  /// Smallest and largest supported table sizes.
  static const int minPlayers = 2;
  static const int maxPlayers = 10;

  /// Names assigned to bots, in seat order (enough for a full table).
  static const List<String> botNamePool = [
    'Ada', 'Boris', 'Chen', 'Dora', 'Eli', 'Farah', 'Gus', 'Hana', 'Ivan',
  ];

  int get botCount => playerCount - 1;
}

/// Client-only implementation: the entire game runs on-device. Bots act
/// automatically with a short delay so the table feels alive.
class LocalGameRepository extends GameRepository {
  LocalGameRepository({this.config = const TableConfig()});

  final TableConfig config;
  final BotStrategy _bot = BotStrategy();

  PokerGame? _game;
  bool _botsRunning = false;

  TableSnapshot _snapshot = TableSnapshot.empty;
  @override
  TableSnapshot get snapshot => _snapshot;

  @override
  Future<void> newGame() async {
    final players = <Player>[
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
    );
    await startNextHand();
  }

  @override
  Future<void> startNextHand() async {
    final game = _game;
    if (game == null) {
      await newGame();
      return;
    }
    game.startHand();
    _publish();
    await _runBots();
  }

  @override
  Future<void> submitAction(GameAction action) async {
    final game = _game;
    if (game == null) return;
    final current = game.currentPlayer;
    if (current == null || !current.isHuman) return;

    game.applyAction(action);
    _publish();
    await _runBots();
  }

  /// Advances the game by letting bots act until it's the human's turn or the
  /// hand ends.
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
        final action = _bot.decide(game, current);
        game.applyAction(action);
        _publish();
      }
    } finally {
      _botsRunning = false;
    }
  }

  void _publish() {
    _snapshot = _buildSnapshot();
    notifyListeners();
  }

  TableSnapshot _buildSnapshot() {
    final game = _game!;
    final showdownHappened = game.results.any((r) => r.handValue != null);
    final wonByPlayer = {for (final r in game.results) r.player: r.amountWon};
    final current = game.currentPlayer;

    final seats = <SeatView>[];
    for (var i = 0; i < game.players.length; i++) {
      final p = game.players[i];
      final reveal = p.isHuman || (showdownHappened && p.inHand);
      String? label;
      if (reveal && p.inHand && game.board.length == 5 && p.hole.length == 2) {
        label = HandEvaluator.evaluate([...p.hole, ...game.board]).rank.label;
      }
      seats.add(SeatView(
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
      ));
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
    );
  }
}
