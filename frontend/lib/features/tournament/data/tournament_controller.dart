import 'dart:async';
import 'dart:math';

import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/ai/icm_adjusted_decider.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_read.dart';
import 'package:monte/core/domain/ai/player_stats.dart';
import 'package:monte/core/domain/ai/profile_decider.dart';
import 'package:monte/core/domain/hand_history.dart';
import 'package:monte/features/reads/data/player_stats_store.dart';
import 'package:monte/core/domain/ai/tournament_context.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';
import 'package:monte/features/tournament/data/chronicle_recorder.dart';
import 'package:monte/features/tournament/domain/tournament_chronicle.dart';
import 'package:monte/features/table/data/table_snapshot_projection.dart';
import 'package:monte/features/table/domain/table_snapshot.dart';
import 'package:monte/features/tournament/domain/chip_set.dart';
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
    this.statsService,
    this._identityBySeat = const {},
    this._profileBySeat = const {},
  })  : _deciders = Map.of(deciders),
        _enginePlayers = Map.of(enginePlayers);

  final TournamentState state;
  final SeatManager seatManager;
  final int tableSize;
  final int seed;

  /// The human entrant's id, or null for an all-bots (headless) tournament.
  final String? humanId;

  /// Persistent per-opponent reads (present only in interactive play). Fed the
  /// human's-table hands and consulted by the exploitative pros.
  final OpponentStatsService? statsService;

  /// Seat id (`e0`, `e3`, …) → the stable identity its stats accumulate under:
  /// `'human'` for the human, else the personality's `profile.id`.
  final Map<String, String> _identityBySeat;
  String? _identityOf(String seatId) => _identityBySeat[seatId];

  /// Seat id → its personality, for computing how that opponent (through their
  /// own style bias) reads the human.
  final Map<String, PlayerProfile> _profileBySeat;

  /// The two-way read on a seat for the HUD, or null when untracked.
  SeatRead? readForSeat(String seatId) {
    final svc = statsService;
    if (svc == null) return null;
    final id = _identityOf(seatId);
    if (id == null) return null;
    // Tracked seats always show a card (a "building a read" state before the
    // baseline), so the model is visibly watching from the first hand.
    final mine = PlayerRead.of(svc.book.read(id) ?? PlayerStats());
    PlayerRead? ofMe;
    final observer = _profileBySeat[seatId];
    if (observer != null && id != PlayerStatsBook.humanIdentity) {
      // This opponent's own impression of the human — only the hands it saw.
      final me = svc.book.read(PlayerStatsBook.meKey(id)) ?? PlayerStats();
      ofMe = PlayerRead.perceivedBy(me, observer);
    }
    return SeatRead(mine: mine, ofMe: ofMe);
  }

  final Map<String, DecisionPolicy> _deciders;
  final Map<String, Player> _enginePlayers;

  /// Metagame chronicle powering the post-level recap. Only fed during
  /// interactive play (there's a human watching) — headless sims skip it so a
  /// huge field stays fast.
  final TournamentChronicle chronicle = TournamentChronicle();
  bool get _chronicling => humanId != null;

  /// Turns finished engine hands into the chronicle's factual records.
  late final ChronicleRecorder _recorder = ChronicleRecorder(
    chronicle: chronicle,
    enabled: _chronicling,
    kindForSeat: _kindForSeat,
    profileForSeat: (id) => _profileBySeat[id],
  );

  /// The recap for the level that just ended, surfaced once on the next
  /// tournament snapshot (mirrors [lastColorUp]).
  LevelRecap? lastRecap;

  StandingKind _kindForSeat(String id) {
    if (state.players[id]?.isHuman ?? false) return StandingKind.human;
    final prof = _profileBySeat[id];
    return (prof != null && isAmateurProfile(prof))
        ? StandingKind.amateur
        : StandingKind.pro;
  }

  /// Snapshots the current active field into the chronicle as a level's start.
  /// Per-table button seat (survives roster changes via modulo).
  final Map<int, int> _button = {};
  int _handCounter = 0;

  // ---- Live play (M5) -------------------------------------------------------
  final _tableCtrl = StreamController<TableSnapshot>.broadcast();
  final _tourCtrl = StreamController<TournamentSnapshot>.broadcast();
  final _simCtrl = StreamController<SimProgress>.broadcast();
  PokerGame? _liveGame;
  bool _awaitingHuman = false;
  Duration _botDelay = const Duration(milliseconds: 300);

  /// How many background tables to simulate between event-loop yields — small
  /// enough that the UI stays responsive and repaints the progress bar even
  /// with hundreds of tables, large enough to avoid excessive yield overhead.
  static const int _simYieldEvery = 8;

  /// The human's live table state (seats/board/action).
  Stream<TableSnapshot> get tableStream => _tableCtrl.stream;

  /// The tournament-wide state (level/clock/players-left/payouts/results).
  Stream<TournamentSnapshot> get tournamentStream => _tourCtrl.stream;

  /// Progress of the between-hands background-table simulation, so the UI can
  /// show "simulating table N of M" instead of a bare spinner.
  Stream<SimProgress> get simProgressStream => _simCtrl.stream;
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
    List<PlayerProfile>? botProfiles,
    bool humanSeat = false,
    bool icmAware = true,
    DecisionPolicy Function(String id, int index)? deciderBuilder,
    OpponentStatsService? statsService,
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
    // Stable identity per seat (for accumulating/reading opponent stats): the
    // human is 'human'; a profiled bot is its personality's profile.id (so the
    // same personality pools reads across seats and events).
    final identityBySeat = <String, String>{};
    final profileBySeat = <String, PlayerProfile>{};
    for (var i = 0; i < entrants; i++) {
      final id = 'e$i';
      if (humanSeat && i == 0) {
        identityBySeat[id] = 'human';
      } else if (botProfiles != null) {
        final prof = botProfiles[humanSeat ? i - 1 : i];
        // A real personality is tracked under its durable profile.id (reads
        // persist across sessions). An anonymous field-filler is a one-off
        // instance: tracked this session under an ephemeral `gen:<seat>` key so
        // it still builds and shows reads, but nothing about it is persisted.
        identityBySeat[id] = prof.generated ? 'gen:$id' : prof.id;
        profileBySeat[id] = prof;
      }
    }
    String? identityOfSeat(String seat) => identityBySeat[seat];

    // Deciders are built after the state so each can be wrapped with tournament
    // awareness (ICM/bubble discipline + short-stack push-fold), reading the live
    // state at decision time.
    final deciders = <String, DecisionPolicy>{};
    for (var i = 0; i < entrants; i++) {
      final id = 'e$i';
      final isHuman = humanSeat && i == 0;
      final profile =
          (!isHuman && botProfiles != null) ? botProfiles[humanSeat ? i - 1 : i] : null;
      // Each bot reads from its own perspective: its impression of the human is
      // built only from the hands it shared (see [OpponentStatsService.readsFor]).
      final reads = statsService?.readsFor(identityOfSeat,
          observerId: identityBySeat[id]);
      final base = profile != null
          ? deciderForProfile(profile, random: Random(seed * 1000 + i), reads: reads)
          : (deciderBuilder?.call(id, i) ??
              buildDecider(BotType.heuristic, random: Random(seed * 1000 + i)));
      // ICM discipline (short-stack push/fold + bubble caution) is a *skill*:
      // only competent players (pros, or the default heuristic) get it. A
      // recreational player keeps misplaying short stacks and the bubble, which
      // is exactly where a pro should out-earn them.
      final disciplined = profile == null || !isAmateurProfile(profile);
      deciders[id] = (icmAware && disciplined)
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
      statsService: statsService,
      identityBySeat: identityBySeat,
      profileBySeat: profileBySeat,
    );
  }

  /// Builds the tournament context for a decision: the acting player's stack in
  /// big blinds (from the live engine [stack]) and the ICM bubble factor across
  /// every remaining player's chips. Static so the decider closures can be built
  /// before the controller instance exists.
  static TournamentContext contextOf(
      TournamentState state, int stack, String playerId) {
    final bb = state.currentLevel.bigBlind;
    final remaining = state.playersRemaining;
    // ICM only differs from chip-neutral where the exact recursion runs (final
    // table); above that the model is chip-proportional and the bubble factor is
    // ~1.0. Skipping it there avoids an O(field) scan on *every* bot decision —
    // the cost that made a full 8,000-runner simulation intractable.
    var bubbleFactor = 1.0;
    if (remaining > 1 && remaining <= Icm.exactLimit) {
      final actives = state.activePlayers.toList();
      final stacks = [for (final a in actives) a.chips];
      final idx = actives.indexWhere((a) => a.id == playerId);
      if (idx >= 0) {
        bubbleFactor = Icm.bubbleFactor(stacks, state.payoutTable, idx);
      }
    }
    final stackInBb = bb > 0 ? stack / bb : 100.0;
    return TournamentContext(
      stackInBb: stackInBb,
      bubbleFactor: bubbleFactor,
      playersLeft: state.playersRemaining,
      paidPlaces: state.paidPlaces,
      inMoney: state.inMoney,
      ladderPressure: _ladderPressure(state, stackInBb),
    );
  }

  /// A stack-scaled survival premium in [0,1] for laddering, computed cheaply
  /// (no full-field ICM): it ramps up approaching the money bubble and as the
  /// field shrinks toward the final table, and is muted for comfortable stacks.
  static double _ladderPressure(TournamentState state, double stackInBb) {
    final left = state.playersRemaining;
    final paid = state.paidPlaces;
    if (left <= 1 || paid <= 0) return 0;

    var zone = 0.0;
    if (!state.inMoney) {
      // Pre-money: ramps to 1 right at the bubble (within a ~20% / ≥10 window).
      final toMoney = (left - paid).toDouble();
      final window = (paid * 0.2).clamp(10.0, 1e9);
      zone = (1 - toMoney / window).clamp(0.0, 1.0);
    } else {
      // In the money: mild premium that grows as the final table nears (steep
      // pay jumps at the end), from ~0 at 3 tables out to ~0.6 heads-up.
      zone = (1 - (left - 1) / 26).clamp(0.0, 1.0) * 0.6;
    }
    if (zone <= 0) return 0;
    // Short/medium stacks ladder; deep stacks (~40BB+) accumulate, not ladder.
    final vulnerability = (1 - stackInBb / 40).clamp(0.0, 1.0);
    return zone * vulnerability;
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
        // _playHand already dropped busts from their table's seats.
        _recordBusts(busts, removeFromTables: false);
        if (_maybeFinish()) return;
      }
    }
    if (handForHand) {
      _recordBusts(roundBusts, removeFromTables: false);
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
      chipUnit: _chipUnitFor(level),
      deck: Deck(random: Random(seed * 131071 + table.id * 8191 + _handCounter)),
    )..buttonIndex = (_button[table.id] ?? 0) % enginePlayers.length;

    final pre = {for (final p in enginePlayers) p.id: p.stack};
    game.startHand();
    if (game.isHandOver) return const {}; // not enough funded (defensive)
    // Capture the action list (only when a human's watching → recaps are on) so
    // the level's biggest pot can be replayed street by street.
    final actions = _chronicling ? <ActionRecord>[] : null;
    while (!game.isHandOver) {
      final cur = game.currentPlayer;
      if (cur == null) break;
      final street = game.round;
      final action = _deciders[cur.id]!.decide(game, cur);
      game.applyAction(action);
      actions?.add(ActionRecord(
        playerId: cur.id,
        street: street,
        type: action.type,
        amount: action.amount,
        potAfter: game.pot,
      ));
    }
    _button[table.id] = game.buttonIndex;

    // Sync stacks back to tournament chips and surface bustouts.
    final busts = <String, int>{};
    for (final p in enginePlayers) {
      state.players[p.id]!.chips = p.stack;
      if (p.stack == 0 && state.players[p.id]!.isActive) busts[p.id] = pre[p.id]!;
    }
    _recorder.recordHand(
      game,
      pre: pre,
      tableId: table.id,
      busted: busts.keys.toSet(),
      levelIndex: state.levelIndex,
      averageStack: state.averageStack,
      actions: actions ?? const [],
    );
    // Drop the busted players from *this* table's seats directly — the busts all
    // happened here, so there's no need for the O(tables) scan that made huge
    // fields quadratic. The caller records the finish/payout with the global
    // seat-removal skipped.
    if (busts.isNotEmpty) table.playerIds.removeWhere(busts.containsKey);
    return busts;
  }

  /// The persistent engine player for [id], its stack refreshed from the live
  /// tournament chip count (so rebuys/re-entries take effect).
  Player _synced(String id) {
    final ep = _enginePlayers[id]!;
    ep.stack = state.players[id]!.chips;
    return ep;
  }

  void _recordBusts(Map<String, int> busts, {bool removeFromTables = true}) {
    if (busts.isEmpty) return;
    final ordered = busts.keys.toList()
      ..sort((a, b) => busts[a]!.compareTo(busts[b]!)); // fewest chips = worst place
    state.recordBustouts(ordered, removeFromTables: removeFromTables);
  }

  bool _maybeFinish() {
    if (state.playersRemaining > 1) return false;
    state.declareChampion();
    return true;
  }

  void _tickLevel() {
    final before = state.currentLevel;
    switch (state.structure.clockMode) {
      case LevelClockMode.hands:
        state.handsThisLevel++;
      case LevelClockMode.minutes:
        // Headless: advance a nominal wall-clock slice per round of hands.
        state.clockElapsed += const Duration(minutes: 2);
    }
    if (state.maybeAdvanceLevel()) {
      _maybeColorUp(before, state.currentLevel);
      _buildRecap(before.level, before.bigBlind);
      _recorder.beginLevel(state.activePlayers); // snapshot the new level's starting stacks
    }
  }

  /// Builds and stores the recap for the level [levelJustFinished] just closed.
  void _buildRecap(int levelJustFinished, int bigBlind) {
    if (!_chronicling) return;
    final currentChips = {
      for (final p in state.activePlayers) p.id: p.chips,
    };
    final finishPlaces = <String, int>{};
    final prizes = <String, int>{};
    for (final p in state.players.values) {
      if (p.finishPlace != null) finishPlaces[p.id] = p.finishPlace!;
      if (p.prizeWon > 0) prizes[p.id] = p.prizeWon;
    }
    lastRecap = chronicle.buildRecap(
      levelJustFinished: levelJustFinished,
      playersLeft: state.playersRemaining,
      averageStack: state.averageStack,
      bigBlind: bigBlind,
      paidPlaces: state.paidPlaces,
      inMoney: state.inMoney,
      humanId: humanId!,
      currentChips: currentChips,
      finishPlaces: finishPlaces,
      prizes: prizes,
    );
  }

  /// The most recent color-up (chip race), for the snapshot/UI to display once.
  ColorUpEvent? lastColorUp;

  /// If the new level retires a chip denomination, races off every active
  /// player's odd chips into whole new-unit chips (total conserved), applies the
  /// deltas to their stacks, and records the event for display.
  void _maybeColorUp(BlindLevel before, BlindLevel after) {
    final oldUnit = _chipUnitFor(before);
    final newUnit = _chipUnitFor(after);
    if (newUnit <= oldUnit) return;
    final stacks = {for (final p in state.activePlayers) p.id: p.chips};
    final deltas = chips.colorUp(stacks, newUnit);
    final nonZero = <String, int>{};
    deltas.forEach((id, d) {
      if (d != 0) {
        state.players[id]!.chips += d;
        nonZero[id] = d;
      }
    });
    lastColorUp =
        ColorUpEvent(oldUnit: oldUnit, newUnit: newUnit, deltas: nonZero);
  }

  // ---- Live play (M5): the human plays their table; others sim between hands --

  /// Begins interactive play. The human's table runs live (pausing on their
  /// turn); every other table simulates one hand between the human's hands.
  Future<void> startLive({Duration botDelay = const Duration(milliseconds: 300)}) {
    _botDelay = botDelay;
    _recorder.beginLevel(state.activePlayers); // snapshot level 1's starting stacks
    _publishTournament();
    return _beginHumanHand();
  }

  /// Whether the live loop is paused waiting for the human to act.
  bool get awaitingHuman => _awaitingHuman;

  /// The human's live table game, or null when no hand is in progress.
  PokerGame? get liveGame => _liveGame;

  /// Applies the human's chosen action and continues the hand.
  Future<void> submitLiveAction(GameAction action) async {
    if (!_awaitingHuman || _liveGame == null) return;
    _awaitingHuman = false;
    _applyLive(_liveGame!, humanId ?? 'e0', action);
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
      await _finishHeadless();
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
      chipUnit: _chipUnitFor(level),
      deck: Deck(random: Random(seed * 131071 + tableId * 8191 + ++_handCounter)),
    )..buttonIndex = (_button[tableId] ?? 0) % enginePlayers.length;
    _preChipsLive = {for (final p in enginePlayers) p.id: p.stack};
    _liveGame!.startHand();
    // Snapshot the seats/blinds for the hand's stats record (masked cards — the
    // read model only needs actions + positions, never hole cards).
    if (statsService != null) {
      final btn = _liveGame!.buttonIndex;
      _liveHandNumber = _handCounter;
      _livePlayers = [
        for (var i = 0; i < enginePlayers.length; i++)
          HandPlayer(
            id: enginePlayers[i].id,
            name: enginePlayers[i].name,
            startingStack: _preChipsLive[enginePlayers[i].id] ?? 0,
            holeCards: const [],
            isButton: i == btn,
            revealed: false,
          ),
      ];
      _liveActions = [];
    }
    _publishTable();
    await _runLiveBots();
  }

  Map<String, int> _preChipsLive = const {};
  List<HandPlayer> _livePlayers = [];
  List<ActionRecord> _liveActions = [];
  int _liveHandNumber = 0;

  /// Folds the just-finished human-table hand into the persistent opponent-stats
  /// model, keyed by each seat's stable identity. Your-table-only (per config).
  void _recordLiveHand(PokerGame game) {
    final svc = statsService;
    if (svc == null || _livePlayers.isEmpty) return;
    final level = state.currentLevel;
    final hand = HandHistory(
      handNumber: _liveHandNumber,
      smallBlind: level.smallBlind,
      bigBlind: level.bigBlind,
      players: _livePlayers,
      actions: _liveActions,
      board: [for (final c in game.board) c.code],
      results: [
        for (final r in game.results)
          HandResultRecord(playerId: r.player.id, amountWon: r.amountWon),
      ],
      finalStacks: {for (final p in game.players) p.id: p.stack},
    );
    svc.record(hand, _identityOf);
    _livePlayers = [];
    _liveActions = [];
  }

  /// Applies [action] for [actorId] at the human table, recording it for the
  /// opponent-stats replay (street captured before the engine advances it).
  void _applyLive(PokerGame game, String actorId, GameAction action) {
    final street = game.round;
    game.applyAction(action);
    if (statsService != null) {
      _liveActions.add(ActionRecord(
        playerId: actorId,
        street: street,
        type: action.type,
        amount: action.amount,
        potAfter: game.pot,
      ));
    }
  }

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
      _applyLive(game, cur.id, _deciders[cur.id]!.decide(game, cur));
      _publishTable();
    }
    await _endHumanHand();
  }

  Future<void> _endHumanHand() async {
    final game = _liveGame!;
    final humanTableId = _humanTableId ?? 0;
    _button[humanTableId] = game.buttonIndex;
    // Snapshot the action list before _recordLiveHand clears it, for the replay.
    final liveActions = List<ActionRecord>.of(_liveActions);
    _recordLiveHand(game); // fold this table's hand into the opponent reads
    // Sync chips + record this table's bustouts.
    final busts = <String, int>{};
    for (final p in game.players) {
      state.players[p.id]!.chips = p.stack;
      if (p.stack == 0 && state.players[p.id]!.isActive) {
        busts[p.id] = _preChipsLive[p.id] ?? 0;
      }
    }
    _recorder.recordHand(
      game,
      pre: _preChipsLive,
      tableId: humanTableId,
      busted: busts.keys.toSet(),
      levelIndex: state.levelIndex,
      averageStack: state.averageStack,
      humanTable: true,
      actions: liveActions,
    );
    // Drop busts from the human's table seats locally (avoids the O(tables) scan).
    if (busts.isNotEmpty) {
      final ht = state.tables
          .firstWhere((t) => t.id == humanTableId, orElse: () => state.tables.first);
      ht.playerIds.removeWhere(busts.containsKey);
    }
    _recordBusts(busts, removeFromTables: false);
    if (_maybeFinish()) {
      _publishTournament();
      _publishTable();
      return;
    }
    // Every other table plays exactly one hand between the human's hands, so the
    // whole field advances at the same pace and each table's chips are conserved
    // by real play. This runs cooperatively — yielding to the event loop every
    // few tables and reporting progress — so even an 8,000-runner field (~900
    // tables) doesn't freeze the UI, and the human sees a "table N of M" bar.
    final finished = await _simulateBackgroundTables(humanTableId);
    if (finished) return;
    seatManager.rebalance(state, tableSize);
    _tickLevel();
    _publishTournament();
    await Future<void>.delayed(_botDelay);
    if (_tableCtrl.isClosed) return;
    await _beginHumanHand();
  }

  /// Plays one hand at every non-human table, yielding to the event loop so the
  /// UI stays responsive and can paint the progress bar. Returns true if the
  /// tournament ended during the round (caller should stop). Emits [SimProgress]
  /// as it goes, and a final "done" so the UI hides the bar.
  Future<bool> _simulateBackgroundTables(int humanTableId) async {
    final tables = [
      for (final t in List.of(state.tables))
        if (t.id != humanTableId && t.size >= 2) t,
    ];
    final total = tables.length;
    for (var i = 0; i < tables.length; i++) {
      _recordBusts(_playHand(tables[i]), removeFromTables: false);
      if (_maybeFinish()) {
        _emitSim(total, total);
        _publishTournament();
        return true;
      }
      if (i % _simYieldEvery == 0 || i == tables.length - 1) {
        _emitSim(i + 1, total);
        await Future<void>.delayed(Duration.zero);
        if (_tableCtrl.isClosed) return true;
      }
    }
    _emitSim(total, total); // done → UI hides the bar
    return false;
  }

  void _emitSim(int done, int total) {
    if (!_simCtrl.isClosed) _simCtrl.add(SimProgress(done: done, total: total));
  }

  /// The physical chips in play. Every wager is snapped to [_chipUnitFor] the
  /// current level, and a color-up (chip race) runs when that unit rises.
  final ChipSet chips = ChipSet.wsop();

  /// The smallest chip denomination still needed at [level] — the granularity
  /// every bet at that level must respect.
  int _chipUnitFor(BlindLevel level) => chips.smallestChip(
        smallBlind: level.smallBlind,
        bigBlind: level.bigBlind,
        ante: level.ante,
      );

  /// The human is out (busted or railing): resolve the rest with real hands so
  /// there's a proper champion and full standings. Bounded — a deep 8,000-runner
  /// finish is millions of hands; if it runs past the budget we settle the
  /// remaining places by chip count (nobody is watching these hands, and the
  /// human's own place was locked in when they busted).
  Future<void> _finishHeadless() async {
    _liveGame = null;
    // Final tables (few players left): resolve fully for a real champion — it's
    // quick, and we yield between rounds so the UI never freezes. Otherwise the
    // human busted deep in a big field; settle the remaining places by chip
    // count instantly rather than grinding thousands of unwatched hands (which
    // read as a hang).
    const resolveBelow = 72;
    if (state.playersRemaining <= resolveBelow) {
      final budget = _handCounter + 40000;
      while (state.status != TournamentStatus.finished && _handCounter < budget) {
        step();
        await Future<void>.delayed(Duration.zero);
        if (_tourCtrl.isClosed) return;
      }
    }
    if (state.status != TournamentStatus.finished) _settleByChips();
    _publishTournament();
  }

  /// Ends a still-running tournament immediately by ranking the remaining active
  /// players by chips: the shortest stacks take the worst open places and the
  /// chip leader is crowned champion. Only used as the budget backstop for a
  /// huge unobserved field (see [_finishHeadless]).
  void _settleByChips() {
    final active = state.activePlayers.toList()
      ..sort((a, b) => a.chips.compareTo(b.chips)); // worst (shortest) first
    if (active.length > 1) {
      state.recordBustouts(
        [for (final p in active.take(active.length - 1)) p.id],
        removeFromTables: false,
      );
    }
    state.declareChampion();
  }

  void _publishTable() {
    if (_liveGame == null || _tableCtrl.isClosed) return;
    // Anchor the human at the bottom-centre seat wherever they've been reseated.
    _tableCtrl.add(
      projectTableSnapshot(
        _liveGame!,
        frontPlayerId: humanId,
        // Colour each seat pro vs recreational, matching the standings panel.
        seatProfiles: _profileBySeat,
        // Draw stacks in the denominations actually in play at this level.
        denominations: chips.denominations,
      ),
    );
  }

  void _publishTournament() {
    if (humanId == null || _tourCtrl.isClosed) return;
    _tourCtrl.add(TournamentSnapshot.of(state, humanId!,
        chipSet: chips, colorUp: lastColorUp, recap: lastRecap));
    lastColorUp = null; // one-shot: only the tick it happened carries it
    lastRecap = null;
  }

  /// The full live standings, built on demand (never broadcast — a huge field
  /// would bloat every snapshot): active players ranked by chips take places
  /// 1..K, then busted players follow in finish order (best finish first).
  List<StandingRow> standings() {
    final active = state.activePlayers.toList()
      ..sort((a, b) => b.chips.compareTo(a.chips));
    final busted = state.players.values.where((p) => !p.isActive).toList()
      ..sort((a, b) =>
          (a.finishPlace ?? 1 << 30).compareTo(b.finishPlace ?? 1 << 30));
    StandingKind kindOf(TournamentPlayer p) {
      if (p.isHuman) return StandingKind.human;
      final prof = _profileBySeat[p.id];
      return (prof != null && isAmateurProfile(prof))
          ? StandingKind.amateur
          : StandingKind.pro;
    }

    bool generatedOf(TournamentPlayer p) =>
        _profileBySeat[p.id]?.generated ?? false;

    final rows = <StandingRow>[];
    var place = 1;
    for (final p in active) {
      rows.add(StandingRow(
        place: place++,
        name: p.name,
        isHuman: p.isHuman,
        chips: p.chips,
        busted: false,
        prize: 0,
        kind: kindOf(p),
        generated: generatedOf(p),
      ));
    }
    for (final p in busted) {
      rows.add(StandingRow(
        place: p.finishPlace ?? place++,
        name: p.name,
        isHuman: p.isHuman,
        chips: 0,
        busted: true,
        prize: p.prizeWon,
        kind: kindOf(p),
        generated: generatedOf(p),
      ));
    }
    return rows;
  }

  void dispose() {
    _tableCtrl.close();
    _tourCtrl.close();
    _simCtrl.close();
  }
}
