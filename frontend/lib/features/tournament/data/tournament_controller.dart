import 'dart:async';
import 'dart:math';

import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/ai/icm_adjusted_decider.dart';
import 'package:monte/core/domain/ai/tournament_context.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';
import 'package:monte/features/table/data/table_snapshot_projection.dart';
import 'package:monte/features/table/domain/table_snapshot.dart';
import 'package:monte/features/tournament/domain/icm.dart';
import 'package:monte/features/tournament/domain/payout_structure.dart';
import 'package:monte/features/tournament/domain/seat_manager.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart';
import 'package:monte/features/tournament/domain/tournament_state.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

/// Drives a full multi-table tournament on top of the single-table [PokerGame]
/// engine. It owns one engine [Player] per entrant (the chip source of truth
/// during a hand), builds a fresh [PokerGame] per table per hand from the current
/// roster + blind level (so rising blinds/antes and seat moves never touch a hand
/// in progress or `clone()`), records bustouts into the [TournamentState], and
/// rebalances tables between hands — running hand-for-hand on the money bubble.
///
/// This layer is headless and deterministic (seeded): the live/human table facade
/// and the UI come later (M5/M6). Everything here is framework-free.
class TournamentController {
  TournamentController._({
    required this.state,
    required this.seatManager,
    required this.tableSize,
    required this.seed,
    required this.humanId,
    required Map<String, DecisionPolicy> deciders,
    required Map<String, Player> enginePlayers,
  })  : _deciders = Map.of(deciders),
        _enginePlayers = Map.of(enginePlayers);

  final TournamentState state;
  final SeatManager seatManager;
  final int tableSize;
  final int seed;

  /// The human entrant's id, or null for an all-bots (headless) tournament.
  final String? humanId;

  final Map<String, DecisionPolicy> _deciders;
  final Map<String, Player> _enginePlayers;

  /// Per-table button seat (survives roster changes via modulo).
  final Map<int, int> _button = {};
  int _handCounter = 0;

  // ---- Live play (M5) -------------------------------------------------------
  final _tableCtrl = StreamController<TableSnapshot>.broadcast();
  final _tourCtrl = StreamController<TournamentSnapshot>.broadcast();
  PokerGame? _liveGame;
  bool _awaitingHuman = false;
  Duration _botDelay = const Duration(milliseconds: 300);

  /// The human's live table state (seats/board/action).
  Stream<TableSnapshot> get tableStream => _tableCtrl.stream;

  /// The tournament-wide state (level/clock/players-left/payouts/results).
  Stream<TournamentSnapshot> get tournamentStream => _tourCtrl.stream;
  int get handsPlayed => _handCounter;

  /// Called after each round of hands — a hook for progress logging / snapshots.
  void Function()? onRound;

  /// Builds a tournament: seats [entrants] players across tables of [tableSize],
  /// each with a decider (defaults to the fast heuristic brain). Seat 0 is the
  /// human if [humanSeat] (still bot-played until the live facade lands).
  factory TournamentController.create({
    required TournamentStructure structure,
    required int entrants,
    required int buyIn,
    required int seed,
    int tableSize = 9,
    List<String>? names,
    bool humanSeat = false,
    bool icmAware = true,
    DecisionPolicy Function(String id, int index)? deciderBuilder,
  }) {
    final players = <String, TournamentPlayer>{};
    final engine = <String, Player>{};
    for (var i = 0; i < entrants; i++) {
      final id = 'e$i';
      final name = (names != null && i < names.length) ? names[i] : 'P${i + 1}';
      final isHuman = humanSeat && i == 0;
      players[id] = TournamentPlayer(
          id: id, name: name, isHuman: isHuman, chips: structure.startingStack);
      engine[id] = Player(
          id: id, name: name, stack: structure.startingStack, isHuman: isHuman);
    }
    final state = TournamentState(
      structure: structure,
      payouts: PayoutStructure.forFieldSize(entrants),
      buyIn: buyIn,
      players: players,
      tables: const [],
    );
    // Deciders are built after the state so each can be wrapped with tournament
    // awareness (ICM/bubble discipline + short-stack push-fold), reading the live
    // state at decision time.
    final deciders = <String, DecisionPolicy>{};
    for (var i = 0; i < entrants; i++) {
      final id = 'e$i';
      final base = deciderBuilder?.call(id, i) ??
          buildDecider(BotType.heuristic, random: Random(seed * 1000 + i));
      deciders[id] = icmAware
          ? IcmAdjustedDecider(base, (g, p) => contextOf(state, p.stack, p.id))
          : base;
    }
    final seatManager = SeatManager(Random(seed ^ 0x5f3759df));
    seatManager.seatDraw(state, tableSize);
    return TournamentController._(
      state: state,
      seatManager: seatManager,
      tableSize: tableSize,
      seed: seed,
      humanId: humanSeat ? 'e0' : null,
      deciders: deciders,
      enginePlayers: engine,
    );
  }

  /// Builds the tournament context for a decision: the acting player's stack in
  /// big blinds (from the live engine [stack]) and the ICM bubble factor across
  /// every remaining player's chips. Static so the decider closures can be built
  /// before the controller instance exists.
  static TournamentContext contextOf(
      TournamentState state, int stack, String playerId) {
    final bb = state.currentLevel.bigBlind;
    final actives = state.activePlayers.toList();
    final stacks = [for (final a in actives) a.chips];
    final idx = actives.indexWhere((a) => a.id == playerId);
    final bubbleFactor = (idx >= 0 && actives.length > 1)
        ? Icm.bubbleFactor(stacks, state.payoutTable, idx)
        : 1.0;
    return TournamentContext(
      stackInBb: bb > 0 ? stack / bb : 100,
      bubbleFactor: bubbleFactor,
      playersLeft: state.playersRemaining,
      paidPlaces: state.paidPlaces,
      inMoney: state.inMoney,
    );
  }

  /// Runs the tournament to a champion (bounded by [maxHands] as a safety net).
  void runToCompletion({int maxHands = 200000}) {
    while (state.status != TournamentStatus.finished && _handCounter < maxHands) {
      step();
    }
  }

  /// One round: play a single hand at every playable table, record bustouts
  /// (together, worst-first, on the bubble so finish places are fair), then
  /// rebalance and advance the level clock.
  void step() {
    final handForHand = seatManager.shouldGoHandForHand(state, tableSize);
    state.status =
        handForHand ? TournamentStatus.handForHand : TournamentStatus.running;

    final roundBusts = <String, int>{}; // id -> chips at start of hand
    for (final table in List.of(state.tables)) {
      if (table.size < 2) continue;
      final busts = _playHand(table);
      if (handForHand) {
        roundBusts.addAll(busts);
      } else {
        _recordBusts(busts);
        if (_maybeFinish()) return;
      }
    }
    if (handForHand) {
      _recordBusts(roundBusts);
      if (_maybeFinish()) return;
    }

    seatManager.rebalance(state, tableSize);
    _tickLevel();
    onRound?.call();
  }

  /// Plays one hand at [table] and returns the players who busted (id -> their
  /// chips at the start of the hand, for worst-first place ordering). Does NOT
  /// record them — the caller decides when (immediately, or after the round on
  /// the bubble).
  Map<String, int> _playHand(TournamentTable table) {
    _handCounter++;
    final level = state.currentLevel;
    final seatIds = List<String>.of(table.playerIds);
    final enginePlayers = [
      for (final id in seatIds) _synced(id),
    ];
    final game = PokerGame(
      players: enginePlayers,
      smallBlind: level.smallBlind,
      bigBlind: level.bigBlind,
      ante: level.ante,
      deck: Deck(random: Random(seed * 131071 + table.id * 8191 + _handCounter)),
    )..buttonIndex = (_button[table.id] ?? 0) % enginePlayers.length;

    final pre = {for (final p in enginePlayers) p.id: p.stack};
    game.startHand();
    if (game.isHandOver) return const {}; // not enough funded (defensive)
    while (!game.isHandOver) {
      final cur = game.currentPlayer;
      if (cur == null) break;
      game.applyAction(_deciders[cur.id]!.decide(game, cur));
    }
    _button[table.id] = game.buttonIndex;

    // Sync stacks back to tournament chips and surface bustouts.
    final busts = <String, int>{};
    for (final p in enginePlayers) {
      state.players[p.id]!.chips = p.stack;
      if (p.stack == 0 && state.players[p.id]!.isActive) busts[p.id] = pre[p.id]!;
    }
    return busts;
  }

  /// The persistent engine player for [id], its stack refreshed from the live
  /// tournament chip count (so rebuys/re-entries take effect).
  Player _synced(String id) {
    final ep = _enginePlayers[id]!;
    ep.stack = state.players[id]!.chips;
    return ep;
  }

  void _recordBusts(Map<String, int> busts) {
    if (busts.isEmpty) return;
    final ordered = busts.keys.toList()
      ..sort((a, b) => busts[a]!.compareTo(busts[b]!)); // fewest chips = worst place
    state.recordBustouts(ordered);
  }

  bool _maybeFinish() {
    if (state.playersRemaining > 1) return false;
    state.declareChampion();
    return true;
  }

  void _tickLevel() {
    switch (state.structure.clockMode) {
      case LevelClockMode.hands:
        state.handsThisLevel++;
      case LevelClockMode.minutes:
        // Headless: advance a nominal wall-clock slice per round of hands.
        state.clockElapsed += const Duration(minutes: 2);
    }
    state.maybeAdvanceLevel();
  }

  // ---- Live play (M5): the human plays their table; others sim between hands --

  /// Begins interactive play. The human's table runs live (pausing on their
  /// turn); every other table simulates one hand between the human's hands.
  Future<void> startLive({Duration botDelay = const Duration(milliseconds: 300)}) {
    _botDelay = botDelay;
    _publishTournament();
    return _beginHumanHand();
  }

  /// Applies the human's chosen action and continues the hand.
  Future<void> submitLiveAction(GameAction action) async {
    if (!_awaitingHuman || _liveGame == null) return;
    _awaitingHuman = false;
    _liveGame!.applyAction(action);
    _publishTable();
    await _runLiveBots();
  }

  /// The id of the table the human is currently seated at, or null.
  int? get _humanTableId {
    for (final t in state.tables) {
      if (t.playerIds.contains(humanId)) return t.id;
    }
    return null;
  }

  Future<void> _beginHumanHand() async {
    final id = humanId;
    if (id == null) return;
    // Human out or tournament decided → finish it off headless and publish.
    if (state.status == TournamentStatus.finished ||
        !(state.players[id]?.isActive ?? false)) {
      _finishHeadless();
      _publishTournament();
      return;
    }
    final tableId = _humanTableId;
    if (tableId == null) return;
    final table =
        state.tables.firstWhere((t) => t.id == tableId, orElse: () => state.tables.first);
    final level = state.currentLevel;
    final enginePlayers = [for (final pid in table.playerIds) _synced(pid)];
    _liveGame = PokerGame(
      players: enginePlayers,
      smallBlind: level.smallBlind,
      bigBlind: level.bigBlind,
      ante: level.ante,
      deck: Deck(random: Random(seed * 131071 + tableId * 8191 + ++_handCounter)),
    )..buttonIndex = (_button[tableId] ?? 0) % enginePlayers.length;
    _preChipsLive = {for (final p in enginePlayers) p.id: p.stack};
    _liveGame!.startHand();
    _publishTable();
    await _runLiveBots();
  }

  Map<String, int> _preChipsLive = const {};

  Future<void> _runLiveBots() async {
    final game = _liveGame!;
    while (!game.isHandOver) {
      final cur = game.currentPlayer;
      if (cur == null) break;
      if (cur.id == humanId) {
        _awaitingHuman = true;
        _publishTable();
        return; // wait for submitLiveAction
      }
      await Future<void>.delayed(_botDelay);
      if (_tableCtrl.isClosed) return;
      game.applyAction(_deciders[cur.id]!.decide(game, cur));
      _publishTable();
    }
    await _endHumanHand();
  }

  Future<void> _endHumanHand() async {
    final game = _liveGame!;
    _button[_humanTableId ?? 0] = game.buttonIndex;
    // Sync chips + record this table's bustouts.
    final busts = <String, int>{};
    for (final p in game.players) {
      state.players[p.id]!.chips = p.stack;
      if (p.stack == 0 && state.players[p.id]!.isActive) {
        busts[p.id] = _preChipsLive[p.id] ?? 0;
      }
    }
    _recordBusts(busts);
    if (_maybeFinish()) {
      _publishTournament();
      _publishTable();
      return;
    }
    // Simulate one hand at every other table.
    for (final table in List.of(state.tables)) {
      if (table.id == _humanTableId || table.size < 2) continue;
      _recordBusts(_playHand(table));
      if (_maybeFinish()) {
        _publishTournament();
        return;
      }
    }
    seatManager.rebalance(state, tableSize);
    _tickLevel();
    _publishTournament();
    await Future<void>.delayed(_botDelay);
    if (_tableCtrl.isClosed) return;
    await _beginHumanHand();
  }

  /// Finishes the tournament without the human (they busted, or are railing):
  /// plays remaining tables to a champion headless.
  void _finishHeadless() {
    _liveGame = null;
    runToCompletion();
  }

  void _publishTable() {
    if (_liveGame == null || _tableCtrl.isClosed) return;
    _tableCtrl.add(projectTableSnapshot(_liveGame!));
  }

  void _publishTournament() {
    if (humanId == null || _tourCtrl.isClosed) return;
    _tourCtrl.add(TournamentSnapshot.of(state, humanId!));
  }

  void dispose() {
    _tableCtrl.close();
    _tourCtrl.close();
  }
}
