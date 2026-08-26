import 'dart:async';
import 'dart:math';

import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/ai/icm_adjusted_decider.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_read.dart';
import 'package:monte/core/domain/ai/player_stats.dart';
import 'package:monte/core/domain/ai/profile_decider.dart';
import 'package:monte/core/domain/ai/trigger_observer.dart';
import 'package:monte/core/domain/hand_history.dart';
import 'package:monte/features/coach/domain/hand_coach.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';
import 'package:monte/features/tournament/data/tournament_result_store.dart';
import 'package:monte/features/tournament/domain/tournament_result.dart';
import 'package:monte/features/reads/data/player_stats_store.dart';
import 'package:monte/core/domain/ai/tournament_context.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'dart:math' as math;

import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';
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
import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/mental_state.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/features/tournament/domain/tournament_save.dart';
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
    this.onEvalHandRecorded,
    this.resultStore,
    this.buyIn = 0,
    this._identityBySeat = const {},
    this._profileBySeat = const {},
    TriggerLog? triggerLog,
    MentalTable? mental,
  }) : _deciders = Map.of(deciders),
       _mental = mental ?? MentalTable(),
       _enginePlayers = Map.of(enginePlayers),
       _triggerLog = triggerLog ?? TriggerLog();

  final TournamentState state;
  final SeatManager seatManager;
  final int tableSize;
  final int seed;

  /// The human entrant's id, or null for an all-bots (headless) tournament.
  final String? humanId;

  /// Persistent per-opponent reads (present only in interactive play). Fed the
  /// human's-table hands and consulted by the exploitative pros.
  final OpponentStatsService? statsService;

  /// Full-information tuning/coaching record for the human's table.
  ///
  /// The single-table repository has always written these; the tournament path
  /// never did, so the hands the player actually cares about produced no record
  /// at all and no review was possible for them.
  final void Function(EvalHand hand)? onEvalHandRecorded;

  /// Career record: one row per finished event. The hand log cannot answer a
  /// career question — it knows nothing about buy-ins, places or prizes.
  final TournamentResultStore? resultStore;

  /// What each seat paid to enter, for ROI.
  final int buyIn;

  /// Identifies this sitting, so a review can separate one tournament from the
  /// next.
  final String _sessionId =
      'T${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

  /// The human's graded decisions in the hand in progress.
  List<EvalDecision> _liveDecisions = [];

  /// Seat id (`e0`, `e3`, …) → the stable identity its stats accumulate under:
  /// `'human'` for the human, else the personality's `profile.id`.
  final Map<String, String> _identityBySeat;
  String? _identityOf(String seatId) => _identityBySeat[seatId];

  /// Seat id → its personality, for computing how that opponent (through their
  /// own style bias) reads the human.
  final Map<String, PlayerProfile> _profileBySeat;

  /// Seat id → the personality seated there, for saving and restoring a field.
  Map<String, PlayerProfile> get profileBySeat =>
      Map.unmodifiable(_profileBySeat);

  /// Captures the tournament so it can be resumed later.
  ///
  /// Taken at a hand boundary: the hand in flight is not part of the save (see
  /// [TournamentSave]), so a reload deals fresh from these chip counts.
  TournamentSave saveAs(String name, {DateTime? at, String? structureName}) =>
      TournamentSave.from(
        name: name,
        savedAt: at ?? DateTime.now(),
        state: state,
        seed: seed,
        tableSize: tableSize,
        humanId: humanId,
        humanName: humanId == null
            ? 'You'
            : (state.players[humanId!]?.name ?? 'You'),
        structureName: structureName ?? _presetNameFor(state.structure),
        profileIds: {for (final e in _profileBySeat.entries) e.key: e.value.id},
      );

  /// Which preset a structure came from, by matching its name.
  static String _presetNameFor(TournamentStructure s) {
    for (final key in const ['turbo', 'standard', 'deep', 'circuit', 'wsop']) {
      if (TournamentStructure.presetByName(key)?.name == s.name) return key;
    }
    return 'standard';
  }

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
    return SeatRead(mine: mine, ofMe: ofMe, live: _liveReads(seatId, ofMe));
  }

  /// Reads that come from the state of this session rather than from history.
  ///
  /// Tilt lives in [MentalTable] and had never left the domain — the bots have
  /// been steaming at each other invisibly. A heater is table image rather than
  /// strategy, but it is what a real player notices first. And the last one is
  /// the read worth having: an opponent who both *tracks* opponents and has an
  /// established book on you is the one beating you in specific spots.
  List<LiveRead> _liveReads(String seatId, PlayerRead? ofMe) {
    final out = <LiveRead>[];

    // Stack geometry first: whether a call can end your tournament is the fact
    // that reframes every other read on the card.
    final them = state.players[seatId];
    final me = humanId == null ? null : state.players[humanId!];
    final bb = state.currentLevel.bigBlind;
    if (them != null && bb > 0) {
      final depth = them.chips / bb;
      if (depth <= 12) {
        // Below roughly a dozen big blinds their game collapses to jam-or-fold
        // (see PushFoldChart) and should be played against completely
        // differently. That was modelled on their side and invisible on yours.
        out.add(
          LiveRead('short — jamming ${depth.round()}bb', LiveReadKind.stack),
        );
      }
    }

    final mood = _mental.stateFor(seatId);
    if (mood != null && mood.isTilted) {
      out.add(
        LiveRead(
          mood.tiltPressure >= 0.7 ? 'steaming' : 'rattled',
          LiveReadKind.tilt,
        ),
      );
    }
    final rush = _recentNet[seatId] ?? 0;
    if (bb > 0 && rush >= 40 * bb) {
      out.add(const LiveRead('running hot', LiveReadKind.rush));
    } else if (bb > 0 && rush <= -40 * bb) {
      out.add(const LiveRead('taking a beating', LiveReadKind.rush));
    }
    // Three gates, because the first version had one and it was useless.
    //
    // The threshold was 0.6, which is exactly `_p`'s default for `oppRead` —
    // so 210 of 218 pros cleared it and the chip appeared on every seat at the
    // table. A warning that is always on is not a warning. It has to be above
    // the default to mean anything, and 0.85 leaves 26 profiles: about one per
    // full table, which is what "this particular player has your number" should
    // feel like.
    //
    // And watching is not the same as having found something. The read must
    // also be confident *and* have produced concrete tendencies — tags are only
    // emitted once there is a real sample behind them — so the chip means they
    // have identified something specific about you, not merely that they were
    // present.
    final observer = _profileBySeat[seatId];
    if (observer != null && ofMe != null && !ofMe.thin) {
      final tracks = observer.behavioralModifiers.weightOnOpponentHistory;
      if (tracks >= 0.85 && ofMe.confidence >= 0.7 && ofMe.tags.isNotEmpty) {
        out.add(const LiveRead('has your number', LiveReadKind.danger));
      }
    }
    return out;
  }

  /// Rolling chip swing per seat over the last few orbits, for the heater read.
  final Map<String, int> _recentNet = {};
  static const _rushWindow = 18;
  final Map<String, List<int>> _recentHands = {};

  void _noteSwing(String seatId, int delta) {
    final h = _recentHands.putIfAbsent(seatId, () => <int>[])..add(delta);
    if (h.length > _rushWindow) h.removeAt(0);
    _recentNet[seatId] = h.fold(0, (a, b) => a + b);
  }

  final Map<String, DecisionPolicy> _deciders;

  /// The policy driving [seatId], for a replay that needs the same opponents.
  DecisionPolicy? deciderFor(String seatId) => _deciders[seatId];

  /// Signature moves fired during the hand in progress. Drained into each
  /// recorded hand so the recap can name the move a player made, then cleared.
  /// Session-scoped and in-memory: it describes one hand, never persisted.
  ///
  /// Created in [create] rather than here because the deciders that write into
  /// it are built before the controller exists.
  final TriggerLog _triggerLog;

  /// Per-tournament tilt, fed every finished hand.
  final MentalTable _mental;
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
  /// Resumes a saved tournament.
  ///
  /// The personalities are looked up by id so the same field comes back, rather
  /// than a fresh random one wearing the saved names. Anyone whose profile has
  /// since been deleted is seated with the default brain rather than dropping
  /// the save — an unreadable save is worse than an approximate one.
  factory TournamentController.restore(
    TournamentSave save, {
    OpponentStatsService? statsService,
    void Function(EvalHand hand)? onEvalHandRecorded,
    TournamentResultStore? resultStore,
    bool icmAware = true,
  }) {
    final structure = save.structure;
    if (structure == null) {
      throw StateError('unknown blind structure "${save.structureName}"');
    }
    final byId = {
      for (final p in [...builtInProfiles, ...homeGameProfiles]) p.id: p,
    };
    // Seats are `e0`, `e1`, ... so they must be ordered *numerically*. Sorting
    // the ids as strings puts `e10` before `e2` and hands every seat past the
    // ninth somebody else's personality.
    int seatIndex(String id) =>
        int.tryParse(id.replaceFirst(RegExp('^[^0-9]*'), '')) ?? 0;
    final humanFirst = [...save.players]
      ..sort((a, b) => seatIndex(a.id).compareTo(seatIndex(b.id)));
    final hasHuman = humanFirst.isNotEmpty && humanFirst.first.isHuman;
    final bots = <PlayerProfile>[
      for (final p in humanFirst.skip(hasHuman ? 1 : 0))
        byId[save.profileIds[p.id]] ?? builtInProfiles.first,
    ];
    return TournamentController.create(
      structure: structure,
      entrants: save.players.length,
      buyIn: save.buyIn,
      seed: save.seed,
      tableSize: save.tableSize,
      names: [for (final p in humanFirst) p.name],
      botProfiles: bots,
      humanSeat: hasHuman,
      icmAware: icmAware,
      statsService: statsService,
      onEvalHandRecorded: onEvalHandRecorded,
      resultStore: resultStore,
      restoreFrom: save,
    );
  }

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
    void Function(EvalHand hand)? onEvalHandRecorded,
    TournamentResultStore? resultStore,
    TournamentSave? restoreFrom,
  }) {
    // One log per tournament: the deciders write signature moves into it, the
    // recorder drains it per hand so the recap can name them.
    final triggerLog = TriggerLog();
    // One mental table per tournament: seats accumulate tilt across the whole
    // event, which is the only timescale on which it means anything.
    final mental = MentalTable();
    final players = <String, TournamentPlayer>{};
    final engine = <String, Player>{};
    if (restoreFrom != null) {
      // Rebuild the field exactly as it was left: chips, seats, who is out.
      for (final sp in restoreFrom.players) {
        final p = sp.toPlayer();
        players[p.id] = p;
        engine[p.id] = Player(
          id: p.id,
          name: p.name,
          stack: p.chips,
          isHuman: p.isHuman,
        );
      }
    } else {
      for (var i = 0; i < entrants; i++) {
        final id = 'e$i';
        final name = (names != null && i < names.length)
            ? names[i]
            : 'P${i + 1}';
        final isHuman = humanSeat && i == 0;
        players[id] = TournamentPlayer(
          id: id,
          name: name,
          isHuman: isHuman,
          chips: structure.startingStack,
        );
        engine[id] = Player(
          id: id,
          name: name,
          stack: structure.startingStack,
          isHuman: isHuman,
        );
      }
    }
    // Built in one go rather than mutated afterwards: the active-player count is
    // derived at construction, so restoring statuses after the fact would leave
    // it stale and every "players remaining" reading wrong.
    final state = restoreFrom == null
        ? TournamentState(
            structure: structure,
            payouts: PayoutStructure.forFieldSize(entrants),
            buyIn: buyIn,
            players: players,
            tables: const [],
          )
        : TournamentState(
            structure: structure,
            payouts: restoreFrom.payouts,
            buyIn: buyIn,
            players: players,
            tables: [
              for (final t in restoreFrom.tables)
                TournamentTable(id: t.id, playerIds: List.of(t.playerIds)),
            ],
            levelIndex: restoreFrom.levelIndex,
            handsThisLevel: restoreFrom.handsThisLevel,
            clockElapsed: Duration(milliseconds: restoreFrom.clockElapsedMs),
            finishOrder: List.of(restoreFrom.finishOrder),
            prizePool: restoreFrom.prizePool,
            status: TournamentStatus.values.firstWhere(
              (v) => v.name == restoreFrom.status,
              orElse: () => TournamentStatus.running,
            ),
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
      final profile = (!isHuman && botProfiles != null)
          ? botProfiles[humanSeat ? i - 1 : i]
          : null;
      // Each bot reads from its own perspective: its impression of the human is
      // built only from the hands it shared (see [OpponentStatsService.readsFor]).
      final reads = statsService?.readsFor(
        identityOfSeat,
        observerId: identityBySeat[id],
      );
      final base = profile != null
          ? deciderForProfile(
              profile,
              random: Random(seed * 1000 + i),
              reads: reads,
              triggers: triggerLog,
              mental: mental,
            )
          : (deciderBuilder?.call(id, i) ??
                buildDecider(
                  BotType.heuristic,
                  random: Random(seed * 1000 + i),
                ));
      // ICM discipline (short-stack push/fold + bubble/ladder folding caution)
      // is a *skill*: only competent players (pros, or the default heuristic)
      // get it. A recreational player keeps misplaying short stacks and the
      // bubble, which is exactly where a pro should out-earn them.
      //
      // Survival-pressure size damping and the garbage-call trim are not that
      // skill, though — every seat is wrapped so both apply universally
      // (`IcmAdjustedDecider`'s `icmDiscipline` flag gates only the ICM-math
      // pieces), which is what tempers amateur pot-bloat without erasing their
      // looseness.
      final disciplined = profile == null || !isAmateurProfile(profile);
      deciders[id] = icmAware
          ? IcmAdjustedDecider(
              base,
              (g, p) => contextOf(state, p.stack, p.id),
              profile: profile,
              triggers: triggerLog,
              icmDiscipline: disciplined,
              random: Random(seed * 977 + i),
            )
          : base;
    }
    final seatManager = SeatManager(Random(seed ^ 0x5f3759df));
    // A restored tournament already has its seating; drawing again would
    // reshuffle everyone and throw away the table dynamics that were saved.
    if (restoreFrom == null) seatManager.seatDraw(state, tableSize);
    return TournamentController._(
      state: state,
      seatManager: seatManager,
      tableSize: tableSize,
      seed: seed,
      humanId: humanSeat ? 'e0' : null,
      deciders: deciders,
      enginePlayers: engine,
      statsService: statsService,
      onEvalHandRecorded: onEvalHandRecorded,
      triggerLog: triggerLog,
      mental: mental,
      identityBySeat: identityBySeat,
      profileBySeat: profileBySeat,
    );
  }

  /// Builds the tournament context for a decision: the acting player's stack in
  /// big blinds (from the live engine [stack]) and the ICM bubble factor across
  /// every remaining player's chips. Static so the decider closures can be built
  /// before the controller instance exists.
  static TournamentContext contextOf(
    TournamentState state,
    int stack,
    String playerId,
  ) {
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
    while (state.status != TournamentStatus.finished &&
        _handCounter < maxHands) {
      step();
    }
  }

  /// One round: play a single hand at every playable table, record bustouts
  /// (together, worst-first, on the bubble so finish places are fair), then
  /// rebalance and advance the level clock.
  void step() {
    final handForHand = seatManager.shouldGoHandForHand(state, tableSize);
    state.status = handForHand
        ? TournamentStatus.handForHand
        : TournamentStatus.running;

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

    _noteTableBreak(
      seatManager.rebalance(state, tableSize, protect: _featureTables()),
    );
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
    final enginePlayers = [for (final id in seatIds) _synced(id)];
    final game = PokerGame(
      players: enginePlayers,
      smallBlind: level.smallBlind,
      bigBlind: level.bigBlind,
      ante: level.ante,
      chipUnit: _chipUnitFor(level),
      deck: Deck(
        random: Random(seed * 131071 + table.id * 8191 + _handCounter),
      ),
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
      actions?.add(
        ActionRecord(
          playerId: cur.id,
          street: street,
          type: action.type,
          amount: action.amount,
          potAfter: game.pot,
        ),
      );
    }
    _button[table.id] = game.buttonIndex;

    // Sync stacks back to tournament chips and surface bustouts.
    final busts = <String, int>{};
    for (final p in enginePlayers) {
      state.players[p.id]!.chips = p.stack;
      if (p.stack == 0 && state.players[p.id]!.isActive)
        busts[p.id] = pre[p.id]!;
    }
    // Tilt accumulates at every table, not just the human's — a player moved to
    // your table part-way through a level should arrive in whatever state their
    // last hour put them in, not freshly calm.
    _mental.observeResults(
      seatIds: [for (final p in enginePlayers) p.id],
      bigBlind: level.bigBlind,
      profileOf: (id) => _profileBySeat[id],
      netOf: (id) => (state.players[id]?.chips ?? 0) - (pre[id] ?? 0),
      enteredPot: (id) => enginePlayers
          .firstWhere((p) => p.id == id, orElse: () => enginePlayers.first)
          .vpip,
    );
    _recorder.recordHand(
      game,
      pre: pre,
      tableId: table.id,
      busted: busts.keys.toSet(),
      levelIndex: state.levelIndex,
      averageStack: state.averageStack,
      actions: actions ?? const [],
      firedTriggers: _triggerLog.drain(),
      notables: _notablesAt(game),
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
      ..sort(
        (a, b) => busts[a]!.compareTo(busts[b]!),
      ); // fewest chips = worst place
    state.recordBustouts(ordered, removeFromTables: removeFromTables);
  }

  bool _maybeFinish() {
    if (state.playersRemaining > 1) return false;
    state.declareChampion();
    _recordCareer();
    return true;
  }

  /// Writes the finished event to the career store, once.
  ///
  /// Recorded at the champion, which includes the stretch played out headless
  /// after the human busted — so a career page reflects whole fields rather
  /// than only the events its owner survived.
  bool _careerRecorded = false;
  void _recordCareer() {
    final store = resultStore;
    if (store == null || _careerRecorded) return;
    _careerRecorded = true;
    final faced = _facedHuman;
    store.record(
      TournamentResult(
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        structureName: state.structure.name,
        buyIn: buyIn,
        entrants: state.players.length,
        finishes: [
          for (final p in state.players.values)
            TournamentFinish(
              profileId:
                  _profileBySeat[p.id]?.id ?? (p.isHuman ? 'human' : p.id),
              name: p.name,
              place: p.finishPlace ?? 0,
              prize: p.prizeWon,
              isHuman: p.isHuman,
              facedHuman: faced.contains(p.id),
            ),
        ],
      ),
    );
  }

  /// Everyone who has shared a table with the human at any point. A field-wide
  /// record is more complete; this is what makes it meaningful, since these are
  /// the only players actually played against.
  final Set<String> _facedHuman = {};

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
      _recorder.beginLevel(
        state.activePlayers,
      ); // snapshot the new level's starting stacks
    }
  }

  /// Builds and stores the recap for the level [levelJustFinished] just closed.
  void _buildRecap(int levelJustFinished, int bigBlind) {
    if (!_chronicling) return;
    final currentChips = {for (final p in state.activePlayers) p.id: p.chips};
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
    // The race runs across the whole field — every stack has to be rounded to
    // the new unit — but only the player's own table is worth *showing*. A
    // thousand-runner race lists nine hundred strangers gaining and losing odd
    // chips, which buries the one line the player came for: what happened to
    // them and to the people they are sitting with.
    final here = humanId == null
        ? null
        : state.tables
              .where((t) => t.playerIds.contains(humanId))
              .firstOrNull
              ?.playerIds
              .toSet();
    final shown = here == null
        ? nonZero
        : {
            for (final e in nonZero.entries)
              if (here.contains(e.key)) e.key: e.value,
          };
    lastColorUp = ColorUpEvent(
      oldUnit: oldUnit,
      newUnit: newUnit,
      deltas: shown,
    );
  }

  // ---- Live play (M5): the human plays their table; others sim between hands --

  /// Begins interactive play. The human's table runs live (pausing on their
  /// turn); every other table simulates one hand between the human's hands.
  Future<void> startLive({
    Duration botDelay = const Duration(milliseconds: 300),
  }) {
    _botDelay = botDelay;
    _recorder.beginLevel(
      state.activePlayers,
    ); // snapshot level 1's starting stacks
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
    if (onEvalHandRecorded != null) {
      _gradeHumanDecision(_liveGame!, action);
    }
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
    final table = state.tables.firstWhere(
      (t) => t.id == tableId,
      orElse: () => state.tables.first,
    );
    final level = state.currentLevel;
    final enginePlayers = [for (final pid in table.playerIds) _synced(pid)];
    _liveGame = PokerGame(
      players: enginePlayers,
      smallBlind: level.smallBlind,
      bigBlind: level.bigBlind,
      ante: level.ante,
      chipUnit: _chipUnitFor(level),
      deck: Deck(
        random: Random(seed * 131071 + tableId * 8191 + ++_handCounter),
      ),
    )..buttonIndex = (_button[tableId] ?? 0) % enginePlayers.length;
    _preChipsLive = {for (final p in enginePlayers) p.id: p.stack};
    _facedHuman.addAll(enginePlayers.map((p) => p.id));
    _liveGame!.startHand();
    // Snapshot the seats/blinds for the hand's stats record (masked cards — the
    // read model only needs actions + positions, never hole cards).
    if (statsService != null || onEvalHandRecorded != null) {
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
    for (final p in game.players) {
      final before = _preChipsLive[p.id];
      if (before != null) _noteSwing(p.id, p.stack - before);
    }
    if (_livePlayers.isEmpty) return;
    // Full-information record first, off the unmasked engine state.
    if (onEvalHandRecorded != null) {
      onEvalHandRecorded!(_buildLiveEvalHand(game));
    }
    final svc = statsService;
    if (svc == null) {
      _livePlayers = [];
      _liveActions = [];
      _liveDecisions = [];
      return;
    }
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
    _liveDecisions = [];
  }

  /// The human table's hand as a full-information [EvalHand] — every seat's real
  /// cards, its personality, the level's ante and the size of the field still
  /// alive, plus the human's graded decisions.
  EvalHand _buildLiveEvalHand(PokerGame game) {
    final level = state.currentLevel;
    final n = game.players.length;
    final starting = _preChipsLive;
    final players = <EvalHandPlayer>[];
    for (final live in game.players) {
      final offset = (game.players.indexOf(live) - game.buttonIndex + n) % n;
      final profile = _profileBySeat[live.id];
      String? foldStreet;
      for (final a in _liveActions) {
        if (a.playerId == live.id && a.type == ActionType.fold) {
          foldStreet = a.street.name;
          break;
        }
      }
      players.add(
        EvalHandPlayer(
          id: live.id,
          name: live.name,
          modelId: profile?.id ?? (live.id == humanId ? 'human' : 'unknown'),
          modelLabel: profile?.name ?? live.name,
          position: positionLabel(offset, n),
          seatsFromButton: offset,
          holeCards: [for (final c in live.hole) c.code],
          startingStack: starting[live.id] ?? live.stack,
          finalStack: live.stack,
          folded: live.hasFolded,
          foldStreet: foldStreet,
          madeHand: game.board.length >= 3 && live.hole.length == 2
              ? HandEvaluator.evaluate([...live.hole, ...game.board]).rank.label
              : null,
          skill: profile?.skill,
          vpipTarget: profile?.strategicBaseline.vpipTarget,
          pfrTarget: profile?.strategicBaseline.pfrTarget,
          threeBetTarget: profile?.strategicBaseline.threeBetFrequency,
        ),
      );
    }
    return EvalHand(
      handNumber: _liveHandNumber,
      smallBlind: level.smallBlind,
      bigBlind: level.bigBlind,
      players: players,
      actions: List.of(_liveActions),
      board: [for (final c in game.board) c.code],
      results: [
        for (final r in game.results)
          HandResultRecord(
            playerId: r.player.id,
            amountWon: r.amountWon,
            handRank: r.handValue?.rank.label,
          ),
      ],
      sessionId: _sessionId,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      ante: level.ante,
      playersRemaining: state.players.values.where((p) => p.isActive).length,
      decisions: List.of(_liveDecisions),
    );
  }

  /// Runs the coach on the spot the human faces and stores what [action] cost
  /// against the coach's own pick. Never allowed to break a hand.
  void _gradeHumanDecision(PokerGame game, GameAction action) {
    final p = game.currentPlayer;
    if (p == null || p.hole.length != 2) return;
    final live = game.players.where((x) => x.inHand && !identical(x, p));
    final eff = live.isEmpty
        ? p.stack
        : math.min(p.stack, live.map((x) => x.stack).reduce(math.max));
    try {
      final r = HandCoach.analyze(
        HandCoachInput(
          hole: p.hole,
          board: game.board,
          pot: game.pot,
          toCall: game.callAmount(p),
          heroCurrentBet: p.currentBet,
          currentBet: game.currentBet,
          effectiveStack: eff,
          bigBlind: game.bigBlind,
          street: game.round,
          raiseCount: game.raiseCountThisRound,
          opponents: live.length,
          opponentLabels: [for (final x in live) x.name],
          canCheck: game.canCheck(p),
          canRaise: p.stack > game.callAmount(p),
          minRaiseTo: game.minRaiseTo(p),
          maxRaiseTo: game.maxRaiseTo(p),
        ),
        analysisAvailable: true,
      );
      if (r.actions.isEmpty) return;
      final best = r.actions[r.recommendedIndex.clamp(0, r.actions.length - 1)];
      final chosen = _matchCoachAction(r.actions, action) ?? best;
      final bb = game.bigBlind <= 0 ? 1 : game.bigBlind;
      _liveDecisions.add(
        EvalDecision(
          playerId: p.id,
          street: game.round.name,
          actualType: action.type.name,
          actualAmount: action.amount,
          potBb: game.pot / bb,
          toCallBb: game.callAmount(p) / bb,
          spr: r.spr,
          equity: r.equity,
          potOdds: r.potOdds,
          chosenLabel: chosen.label,
          // HandCoach returns EV in **chips**. EvalDecision is documented in big
          // blinds, and at tournament stacks the difference is not cosmetic: a
          // session came back reporting 352,111bb of EV given up.
          chosenEv: chosen.ev / bb,
          bestLabel: best.label,
          bestEv: best.ev / bb,
        ),
      );
    } catch (_) {
      // Coaching telemetry must never cost the player a hand.
    }
  }

  ActionEv? _matchCoachAction(List<ActionEv> options, GameAction action) {
    switch (action.type) {
      case ActionType.fold:
        return options.where((o) => o.kind == CoachAction.fold).firstOrNull;
      case ActionType.check:
        return options.where((o) => o.kind == CoachAction.check).firstOrNull;
      case ActionType.call:
        return options.where((o) => o.kind == CoachAction.call).firstOrNull;
      case ActionType.bet:
      case ActionType.raise:
      case ActionType.allIn:
        final sized = options.where((o) => o.toAmount != null).toList();
        if (sized.isEmpty) return null;
        sized.sort(
          (a, b) => (a.toAmount! - action.amount).abs().compareTo(
            (b.toAmount! - action.amount).abs(),
          ),
        );
        return sized.first;
    }
  }

  /// Applies [action] for [actorId] at the human table, recording it for the
  /// opponent-stats replay (street captured before the engine advances it).
  void _applyLive(PokerGame game, String actorId, GameAction action) {
    final street = game.round;
    game.applyAction(action);
    if (statsService != null || onEvalHandRecorded != null) {
      _liveActions.add(
        ActionRecord(
          playerId: actorId,
          street: street,
          type: action.type,
          amount: action.amount,
          potAfter: game.pot,
        ),
      );
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
      firedTriggers: _triggerLog.drain(),
      notables: _notablesAt(game),
    );
    // Drop busts from the human's table seats locally (avoids the O(tables) scan).
    if (busts.isNotEmpty) {
      final ht = state.tables.firstWhere(
        (t) => t.id == humanTableId,
        orElse: () => state.tables.first,
      );
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
    _noteTableBreak(
      seatManager.rebalance(state, tableSize, protect: _featureTables()),
    );
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
      while (state.status != TournamentStatus.finished &&
          _handCounter < budget) {
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
      state.recordBustouts([
        for (final p in active.take(active.length - 1)) p.id,
      ], removeFromTables: false);
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

  /// Tables holding two or more recognisable players. A tournament breaks
  /// somebody else's table before it breaks the one with the cameras on it.
  Set<int> _featureTables() => {
    for (final t in state.tables)
      if (t.playerIds
              .where((id) => _profileBySeat[id]?.generated == false)
              .length >=
          2)
        t.id,
  };

  /// The named personalities dealt into [game] — the ones a viewer would
  /// recognise, as opposed to the anonymous profiles that fill out a field.
  ///
  /// `FieldBuilder` marks auto-filled seats `generated`, so the flag is already
  /// there; nothing had ever asked it a question.
  List<String> _notablesAt(PokerGame game) => [
    for (final p in game.players)
      if (_profileBySeat[p.id]?.generated == false) _profileBySeat[p.id]!.name,
  ];

  /// A table that has just broken, for the next publish. One-shot.
  TableBreakDisplay? _lastTableBreak;

  /// Notes only the seat changes that affect the **human's** table.
  ///
  /// This used to announce whichever table broke anywhere in the field, which
  /// in a large event is a stream of notices about strangers being moved
  /// between tables the player will never see. Two things actually matter: being
  /// moved yourself, and somebody new sitting down opposite you.
  void _noteTableBreak(List<SeatMove> moves) {
    if (moves.isEmpty || humanId == null) return;
    final me = humanId!;

    // Were *we* moved? Then our table broke (or we were balanced away).
    final mine = moves.where((m) => m.playerId == me).firstOrNull;
    if (mine != null) {
      final together = moves.where((m) => m.fromTable == mine.fromTable);
      _lastTableBreak = TableBreakDisplay(
        tableNumber: mine.fromTable + 1,
        broke: true,
        moves: [
          for (final m in together)
            TableBreakMove(
              name: state.players[m.playerId]?.name ?? m.playerId,
              isHuman: m.playerId == me,
              toTable: m.toTable + 1,
              toSeat: m.toSeat,
            ),
        ],
      );
      return;
    }

    // Otherwise: did anyone arrive at our table?
    final here = state.tables
        .where((t) => t.playerIds.contains(me))
        .firstOrNull
        ?.id;
    if (here == null) return;
    final arrived = [
      for (final m in moves)
        if (m.toTable == here) state.players[m.playerId]?.name ?? m.playerId,
    ];
    if (arrived.isEmpty) return;
    _lastTableBreak = TableBreakDisplay(
      tableNumber: here + 1,
      broke: false,
      arrivals: arrived,
      moves: const [],
    );
  }

  void _publishTournament() {
    if (humanId == null || _tourCtrl.isClosed) return;
    _tourCtrl.add(
      TournamentSnapshot.of(
        state,
        humanId!,
        chipSet: chips,
        colorUp: lastColorUp,
        recap: lastRecap,
        tableBreak: _lastTableBreak,
      ),
    );
    lastColorUp = null; // one-shot: only the tick it happened carries it
    lastRecap = null;
    _lastTableBreak = null;
  }

  /// The full live standings, built on demand (never broadcast — a huge field
  /// would bloat every snapshot): active players ranked by chips take places
  /// 1..K, then busted players follow in finish order (best finish first).
  List<StandingRow> standings() {
    final active = state.activePlayers.toList()
      ..sort((a, b) => b.chips.compareTo(a.chips));
    final busted = state.players.values.where((p) => !p.isActive).toList()
      ..sort(
        (a, b) =>
            (a.finishPlace ?? 1 << 30).compareTo(b.finishPlace ?? 1 << 30),
      );
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
      rows.add(
        StandingRow(
          place: place++,
          name: p.name,
          isHuman: p.isHuman,
          chips: p.chips,
          busted: false,
          prize: 0,
          kind: kindOf(p),
          generated: generatedOf(p),
        ),
      );
    }
    for (final p in busted) {
      rows.add(
        StandingRow(
          place: p.finishPlace ?? place++,
          name: p.name,
          isHuman: p.isHuman,
          chips: 0,
          busted: true,
          prize: p.prizeWon,
          kind: kindOf(p),
          generated: generatedOf(p),
        ),
      );
    }
    return rows;
  }

  void dispose() {
    _tableCtrl.close();
    _tourCtrl.close();
    _simCtrl.close();
  }
}
