import 'dart:async';
import 'dart:math';

import 'package:monte/features/tournament/data/background_table_simulator.dart';
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
import 'package:monte/features/tournament/domain/chronicle/hand_narrator.dart';
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

part 'tournament_controller_live.dart';
part 'tournament_controller_background.dart';
part 'tournament_controller_standings.dart';

/// Drives a full multi-table tournament on top of the single-table [PokerGame]
/// engine. It owns one engine [Player] per entrant (the chip source of truth
/// during a hand), builds a fresh [PokerGame] per table per hand from the current
/// roster + blind level (so rising blinds/antes and seat moves never touch a hand
/// in progress or `clone()`), records bustouts into the [TournamentState], and
/// rebalances tables between hands — running hand-for-hand on the money bubble.
///
/// This layer is headless and deterministic (seeded): the live/human table facade
/// and the UI come later (M5/M6). Everything here is framework-free.
///
/// The implementation is split by concern across `part` files, but all as
/// **extensions** on this one class rather than a literal multi-file class
/// body — Dart has no way to split a single class declaration's braces across
/// files. `part`/`part of` still buys the thing that mattered here (this class
/// carries a lot of tightly-coupled private state — see CLAUDE.md's live/
/// background notes — and a real mixin-per-concern split would have forced
/// exposing most of it as protected-ish getters/setters, which is worse than
/// one file): every part below shares this file's *library* scope, so an
/// extension in `tournament_controller_live.dart` can call a private method or
/// field declared in `tournament_controller_background.dart` exactly as if
/// they were still in one file. All instance *fields* stay here (extensions
/// can't declare them); [_TournamentControllerLive] (human hand flow + bot
/// loop), [_TournamentControllerBackground] (background table simulation,
/// chip-drift reconciliation, the level clock) and
/// [_TournamentControllerStandings] (reads/HUD, standings, publishing
/// snapshots) hold the methods.
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
    this._yieldToFrame,
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

  /// True while [_finishHeadless] is grinding out the rest of the field after
  /// the human busted — surfaced on [TournamentSnapshot.resolvingRestOfField]
  /// so the screen can show a dedicated banner instead of a frozen table.
  bool _resolvingHeadless = false;
  Duration _botDelay = const Duration(milliseconds: 300);

  /// How long the player sees the showdown before the next hand deals in.
  /// Separate from [_botDelay] (which paces individual bot actions within a
  /// hand) and independently configurable so tests can zero it out the same
  /// way they already zero out [_botDelay] for speed.
  Duration _nextHandDelay = const Duration(seconds: 2);

  /// How many background tables to simulate between event-loop yields when no
  /// [_yieldToFrame] is supplied (headless/batch simulation) — small enough
  /// that the UI stays responsive and repaints the progress bar even with
  /// hundreds of tables, large enough to avoid excessive yield overhead.
  ///
  /// When [_yieldToFrame] *is* supplied (live play), this is bypassed
  /// entirely and every table yields — see [_simulateBackgroundTables].
  static const int _simYieldEvery = 8;

  /// A real "wait for a frame to actually render" yield, supplied by the
  /// presentation layer (`SchedulerBinding.instance.endOfFrame`) for live
  /// play. Null in headless/batch contexts (`runToCompletion`, tests,
  /// `tool/bench_*.dart`), which fall back to `Future.delayed(Duration.zero)`
  /// — a *microtask* yield, not a frame yield, and the wrong tool for keeping
  /// a real UI responsive: it only queues a continuation, it doesn't wait for
  /// anything to paint. Kept as a plain closure (not a direct
  /// `flutter/scheduler.dart` import) so this data-layer controller stays
  /// framework-free and usable from a pure-Dart script.
  final Future<void> Function()? _yieldToFrame;

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

  // ---- Live play (M5): state used by _TournamentControllerLive --------------

  /// Real time the current level began (live play only) — lets the minutes
  /// clock read actual elapsed time rather than a nominal per-hand estimate,
  /// and lets the real-time timer (see [_startRealtimeTicker]) advance the
  /// level even if the human never acts (a real tournament's clock doesn't
  /// wait for a distracted player).
  DateTime? _levelStartedAt;

  /// Wall-clock time the human's current hand began — read by the away-pause
  /// check (see [_checkAwayPause]).
  DateTime? _humanHandStartedAt;

  /// True from the moment the human's hand is dealt until `_endHumanHand`
  /// finishes settling its results — the window a rebalance must stay out
  /// of, since moving players between tables mid-hand could disturb the
  /// table a live `PokerGame` already fixed.
  ///
  /// **Not** the same as `_liveGame == null`: `_liveGame` is only ever nulled
  /// once the human busts entirely (`_finishHeadless`) — between ordinary
  /// hands it just holds the *previous* hand's finished game, so checking it
  /// for "no hand in progress" was true almost never, and silently blocked
  /// rebalancing (and therefore table breaking) for the rest of the
  /// tournament after the very first hand.
  bool _humanHandActive = false;

  /// Ticks the level clock and the away-pause check in real time, completely
  /// independent of the human's own hand cadence or background simulation —
  /// deliberately the *only* thing on a timer, since it never touches
  /// `state.tables`/`state.players` (see [_startRealtimeTicker]).
  Timer? _realtimeTicker;

  /// The human's graded decisions in the hand in progress.
  List<EvalDecision> _liveDecisions = [];

  Map<String, int> _preChipsLive = const {};
  List<HandPlayer> _livePlayers = [];
  List<ActionRecord> _liveActions = [];
  int _liveHandNumber = 0;

  // ---- Background simulation state used by _TournamentControllerBackground --

  /// Background table simulator for parallel table simulation.
  /// Initialized when tournament starts.
  late final BackgroundTableSimulator _bgSimulator = BackgroundTableSimulator();

  /// Tracks background table simulation so player table doesn't wait for it.
  Future<bool>? _bgSimFuture;

  /// Guards against two overlapping background-simulation rounds mutating
  /// `state.tables`/`state.players` concurrently — see `_endHumanHand`.
  bool _bgSimRunning = false;

  /// A background round finished with busts to rebalance while the human was
  /// already mid-hand again — deferred to the start of the *next* hand rather
  /// than dropped. In a large field a background round (every other table
  /// playing a hand) can take longer than the human's own hand + the next-
  /// hand delay, so the round's completion callback landing while
  /// `_humanHandActive` is true again isn't rare — it's the common case once
  /// the field is big enough. Silently skipping it there (the original
  /// behaviour) meant tables could go a full orbit or more without ever
  /// breaking, since nothing retried.
  bool _rebalancePending = false;

  /// Writes the finished event to the career store, once.
  bool _careerRecorded = false;

  /// Past-event bracelets/rings by identity (`'human'` or profile id), for
  /// the standings' decorations. [TournamentResultStore.loadAll] is async
  /// and file-backed, but `standings()` is called synchronously on every
  /// redraw — loaded once in the background at [startLive] and cached here,
  /// rather than making every standings read touch disk. Empty (not null)
  /// until that load resolves, so a standings read before then just shows
  /// no decorations yet instead of throwing.
  Map<String, WinDecorations> _winDecorations = const {};

  /// The human's most recently completed hand, cached so a "show me the
  /// previous hand" button can display it on demand — see [_endHumanHand].
  /// Null before the human's first hand, or when the hand didn't qualify
  /// for a full replay (see [ReplayBuilder.build]), in which case
  /// [lastHandFallbackSummary] carries a plain-text description instead.
  HandReplay? _lastHandReplay;
  int _lastHandBigBlind = 0;
  String? _lastHandFallbackSummary;

  /// The last hand's replay, narrated on demand — narration enumerates outs
  /// street by street and is only worth paying for if the player actually
  /// asks to see it, unlike the level recap's one feature hand (chosen and
  /// narrated regardless of whether anyone opens it).
  HandReplay? get lastHandReplay =>
      _lastHandReplay == null ? null : HandNarrator.narrate(_lastHandReplay!);
  int get lastHandBigBlind => _lastHandBigBlind;

  /// Set instead of [lastHandReplay] when the hand ended before two players
  /// saw a flop (a walk, or folded around) — too little happened for a full
  /// street-by-street replay, but the player still asked to see it.
  String? get lastHandFallbackSummary => _lastHandFallbackSummary;

  /// A one-line description for a hand [ReplayBuilder.build] declined to
  /// replay — nobody contested the flop, so there's no board/street of
  /// interest, only who took the blinds/antes and from whom.
  String _summarizeUnreplayedHand(PokerGame game, List<ActionRecord> actions) {
    final winner = game.results.where((r) => r.netWon > 0).firstOrNull;
    if (winner == null) return 'No pot was won this hand.';
    final folded = actions
        .where((a) => a.type == ActionType.fold)
        .map((a) => game.players.where((p) => p.id == a.playerId).firstOrNull?.name)
        .whereType<String>()
        .toList();
    final pot = winner.netWon;
    return folded.isEmpty
        ? '${winner.player.name} wins the blinds and antes uncontested.'
        : '${folded.join(', ')} fold${folded.length == 1 ? 's' : ''} — '
              '${winner.player.name} takes the pot ($pot chips) uncontested.';
  }

  /// Loads [_winDecorations] from [resultStore] once, then republishes so
  /// the standings panel picks up any hardware already on record. Fire-
  /// and-forget: nothing in the live flow needs to wait on it.
  void _loadWinDecorations() {
    final store = resultStore;
    if (store == null) return;
    store.loadAll().then((results) {
      _winDecorations = WinDecorations.fromResults(results);
      _publishTournament();
    });
  }

  /// Everyone who has shared a table with the human at any point. A field-wide
  /// record is more complete; this is what makes it meaningful, since these are
  /// the only players actually played against.
  final Set<String> _facedHuman = {};

  /// The most recent color-up (chip race), for the snapshot/UI to display once.
  ColorUpEvent? lastColorUp;

  /// The physical chips in play. Every wager is snapped to `_chipUnitFor` the
  /// current level, and a color-up (chip race) runs when that unit rises.
  final ChipSet chips = ChipSet.wsop();

  /// The smallest denomination the *display* should still draw, right now.
  /// A color-up retires a denomination for good — real chips don't un-retire
  /// — so this only ever rises, tracked in `_maybeColorUp`. `_chipUnitFor`
  /// alone is not monotonic (e.g. the WSOP Circuit ladder needs a 500 unit at
  /// 500/1000 but only a 100 unit at the very next level, 600/1200/1200,
  /// since 600 isn't divisible by 500), which let a level like that draw an
  /// already-retired denomination back onto the felt one level after the
  /// color-up race removed it. Deliberately display-only: betting granularity
  /// itself (`_chipUnitFor`, used for `game.chipUnit`) still follows the raw,
  /// non-monotonic value, which is separately load-bearing behaviour (see
  /// `whole_chips_test.dart`).
  ///
  /// Seeded from every level up to and including the current one (not just the
  /// current one) so a restored save recovers the same running high-water mark
  /// a tournament played straight through would have reached, rather than
  /// whatever the current level alone computes to.
  late int _displayChipUnit = state.structure.levels
      .where((l) => l.level <= state.currentLevel.level)
      .map(_chipUnitFor)
      .fold(1, (a, b) => a > b ? a : b);

  Random? _driftRng;

  // ---- Standings/HUD state used by _TournamentControllerStandings -----------

  /// Rolling chip swing per seat over the last few orbits, for the heater read.
  final Map<String, int> _recentNet = {};
  final Map<String, List<int>> _recentHands = {};

  /// Players who are new to their current table (for first-hand highlight).
  /// Cleared after they play their first hand at the table.
  final Set<String> _newToTablePlayers = {};

  /// Which table each player is at, for detecting when they move to a new table.
  final Map<String, int> _playerTableMap = {};

  /// A table that has just broken, for the next publish. One-shot.
  TableBreakDisplay? _lastTableBreak;

  /// The most recently computed chip-leaders list, reused between the
  /// (throttled) recomputations in [_publishTournament] — see [_finishHeadless].
  List<StandingRow> _cachedTopChipLeaders = const [];

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
    Future<void> Function()? yieldToFrame,
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
      yieldToFrame: yieldToFrame,
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
    Future<void> Function()? yieldToFrame,
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

    // Whether [seatId] is currently seated at the human's own live table
    // (rather than off at a background table) — local rather than an
    // instance method, since this closure is captured before the instance
    // exists (factory constructor).
    bool isAtHumanTable(String seatId) {
      if (!humanSeat) return false;
      final t = state.tables.firstWhere(
        (t) => t.playerIds.contains('e0'),
        orElse: () => state.tables.first,
      );
      return t.playerIds.contains(seatId);
    }

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
              // Read live, not captured here: the cutover to the search
              // evaluator activates the moment the field consolidates to the
              // true final table (`tableCount <= 1`), including through
              // `_finishHeadless`'s resolve-to-completion loop, which reuses
              // these same constructed deciders every hand.
              tableCountProvider: () => state.tables.length,
              // Separate lever: the opponents seated at the human's own live
              // table always reason at full resolution, regardless of how
              // big the rest of the field still is — only seats currently
              // off at a background table get the field-size-scaled count.
              equityTableCountProvider: () =>
                  isAtHumanTable(id) ? 1 : state.tables.length,
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
      resultStore: resultStore,
      buyIn: buyIn,
      triggerLog: triggerLog,
      mental: mental,
      identityBySeat: identityBySeat,
      profileBySeat: profileBySeat,
      yieldToFrame: yieldToFrame,
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

  void dispose() {
    _realtimeTicker?.cancel();
    _bgSimulator.dispose();
    _tableCtrl.close();
    _tourCtrl.close();
    _simCtrl.close();
  }
}
