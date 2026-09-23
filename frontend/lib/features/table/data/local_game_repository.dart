import 'dart:async';
import 'dart:math' as math;

import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/ismcts.dart';
import 'package:monte/core/domain/ai/opponent_model.dart';
import 'package:monte/core/domain/ai/opponent_reads.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/core/domain/ai/player_read.dart';
import 'package:monte/core/domain/ai/player_stats.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/ai/mental_state.dart';
import 'package:monte/core/domain/ai/profile_decider.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/core/domain/engine/player.dart';
import 'package:monte/core/domain/hand_history.dart';
import 'package:monte/features/reads/data/player_stats_store.dart';
import 'package:monte/features/coach/domain/hand_coach.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';
import 'package:monte/features/table/domain/game_repository.dart';
import 'package:monte/features/table/data/table_snapshot_projection.dart';
import 'package:monte/features/table/domain/table_config.dart';
import 'package:monte/features/table/domain/table_snapshot.dart';

/// Re-exported so the many existing `import '.../local_game_repository.dart'`
/// call sites (tests included) keep resolving [TableConfig] after it moved to
/// the domain layer where it belongs.
export 'package:monte/features/table/domain/table_config.dart';

// Split by seam, not by class: these parts share `LocalGameRepository`'s
// private fields directly rather than through normal imports.
part 'local_game_repository_bots.dart';
part 'local_game_repository_recording.dart';
part 'local_game_repository_snapshot.dart';

/// Client-only implementation: the entire game runs on-device. Bots act
/// automatically with a short delay so the table feels alive. In all-bots mode
/// the engine plays itself, recording every hand for analysis.
class LocalGameRepository extends GameRepository {
  LocalGameRepository({this.config = const TableConfig(), this.statsService});

  /// Identifies this sitting, so a review can separate one session from the
  /// next. Derived from the clock at construction; hands carry it verbatim.
  final String _sessionId =
      'S${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

  /// The human's decisions this hand, with the coach's verdict on each.
  List<EvalDecision> _recDecisions = [];

  final TableConfig config;

  /// Persistent per-opponent reads (by `profile.id` / `'human'`). When present,
  /// exploitative pros consult it and each finished hand is folded back in.
  final OpponentStatsService? statsService;

  /// Maps a seat player id (`'human'`, `'bot_2'`) to the stable identity stats
  /// are accumulated under: `'human'` for the human, the personality's
  /// `profile.id` for a profiled bot, or null (untracked heuristic seat).
  String? _identityOf(String seatId) {
    if (seatId == 'human') return 'human';
    final profile = _specByPlayer[seatId]?.profile;
    // Anonymous generated fillers are ephemeral — never tracked (see
    // [PlayerProfile.generated]).
    if (profile == null || profile.generated) return null;
    return profile.id;
  }

  /// Reads bound to bot [playerId]'s own perspective: its impression of the
  /// human comes only from hands it shared with them.
  OpponentReads? _readsAs(String playerId) =>
      statsService?.readsFor(_identityOf, observerId: _identityOf(playerId));

  /// A human-readable read on the player in [seatId] for the HUD, or null if
  /// they're untracked or no reads are being kept.
  SeatRead? readForSeat(String seatId) {
    final svc = statsService;
    if (svc == null) return null;
    final id = _identityOf(seatId);
    if (id == null) return null; // untracked (e.g. a heuristic bot, no profile)
    // A tracked seat with no data yet still shows a "building a read" card, so
    // the player can see the model is watching from hand one.
    final mine = PlayerRead.of(svc.book.read(id) ?? PlayerStats());
    // How this opponent reads the hero — biased by their own style, from only
    // the hands they've actually shared with the human.
    PlayerRead? ofMe;
    final observer = _specByPlayer[seatId]?.profile;
    if (observer != null && id != PlayerStatsBook.humanIdentity) {
      final me = svc.book.read(PlayerStatsBook.meKey(id)) ?? PlayerStats();
      ofMe = PlayerRead.perceivedBy(me, observer);
    }
    return SeatRead(mine: mine, ofMe: ofMe);
  }

  /// One decider per bot seat (keyed by player id), so seats can hold distinct
  /// personalities and a busted seat can be replaced independently.
  final Map<String, DecisionPolicy> _deciders = {};

  /// Per-bot-seat behavior models for the next/current game, in bot-seat order.
  /// Seeded from the config; [newGameWithBots] swaps it for a fresh lineup. Bots
  /// past the end fall back to the table defaults.
  late List<BotSpec> _seatBots = List.of(config.seatBots);

  /// The resolved behavior model per bot seat (keyed by player id), for the
  /// seat badge. Populated as deciders are built.
  final Map<String, BotSpec> _specByPlayer = {};

  /// Per-session opponent reads, fed every finished hand and consulted by
  /// exploitative profile bots' search.
  final OpponentModel _opponentModel = OpponentModel();

  /// How rattled each seat is. Session-scoped and never persisted — nobody sits
  /// down still steaming about a pot from last week.
  final MentalTable _mental = MentalTable();

  PokerGame? _game;
  bool _botsRunning = false;
  bool _disposed = false;

  /// True while [simulate] is running a batch — makes every hand top stacks back
  /// up so an evaluation run never busts out and halts early.
  bool _evaluating = false;

  /// Whether the dealer button rotates; toggled at runtime for evaluation.
  late bool _rotateButton = config.rotateButton;

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
  List<BotSpec> get currentSeatBots => [
    for (final p in _game?.players ?? const <Player>[])
      if (!p.isHuman) _specByPlayer[p.id] ?? const BotSpec(),
  ];

  @override
  List<HandHistory> get history => List.unmodifiable(_history);

  @override
  void clearHistory() {
    _history.clear();
  }

  @override
  void resetMemory() {
    _history.clear();
    _opponentModel.reset();
  }

  @override
  void dispose() {
    _disposed = true;
    if (!_controller.isClosed) _controller.close();
  }

  /// Builds a fresh table (players + engine) without dealing a hand.
  void _createGame() {
    // Name each bot seat after its persona (a named pro's real name, or its
    // archetype), so the table shows who's who; seats with no distinctive
    // persona fall back to the generic name pool.
    final specs = [for (var i = 0; i < config.botCount; i++) _specForSeat(i)];
    final botNames = _seatNamesFor(specs);
    // Toggling to all-bots turns the player's own seat into a bot rather than
    // removing it — it keeps the player's name so the table still reads as
    // "you", just piloted by the personality/brain assigned to that seat.
    if (config.allBots && botNames.isNotEmpty) {
      botNames[0] = config.humanName;
    }
    final players = <Player>[
      if (!config.allBots)
        Player(
          id: 'human',
          name: config.humanName,
          stack: config.startingStack,
          isHuman: true,
        ),
      for (var i = 0; i < config.botCount; i++)
        Player(id: 'bot_$i', name: botNames[i], stack: config.startingStack),
    ];
    _game = PokerGame(
      players: players,
      smallBlind: config.smallBlind,
      bigBlind: config.bigBlind,
      rotateButton: _rotateButton,
      deck: config.deckBuilder?.call(),
    );

    // A decider per bot seat. Each bot uses its per-seat behavior model if one
    // was given, otherwise the table defaults.
    _deciders.clear();
    _specByPlayer.clear();
    var botIndex = 0;
    for (final p in players) {
      if (p.isHuman) continue;
      _deciders[p.id] = _deciderForBot(botIndex, p.id);
      botIndex++;
    }
  }

  /// The lineup to resolve seats against. Identical to [_seatBots] unless
  /// [TableConfig.allBots] has turned the player's own seat into a bot: seat 0
  /// then stands in for the player, playing their own named personality if
  /// [TableConfig.humanName] matches one in the catalog, or a generic decent
  /// amateur if it doesn't (nobody in the pro/home-game roster is a beginner
  /// or a maniac by default). Computed fresh rather than baked into
  /// [_seatBots] so toggling [TableConfig.allBots] off restores the original
  /// lineup untouched.
  List<BotSpec> _effectiveSeatBots() {
    if (!config.allBots || _seatBots.isEmpty) return _seatBots;
    // Replaces seat 0, rather than prepending — the list is already sized to
    // `config.botCount` (== playerCount in all-bots mode), so prepending
    // would push every other seat's configured spec down by one and drop the
    // last seat's entirely.
    final profile = _profileForName(config.humanName) ?? justinVidovitch;
    return [BotSpec(profile: profile), ..._seatBots.skip(1)];
  }

  /// A catalog profile (pro or home-game) whose name matches [name], ignoring
  /// case and surrounding whitespace — so playing yourself as a bot plays like
  /// *you*, when you happen to share a name with someone in the catalog.
  static PlayerProfile? _profileForName(String name) {
    final needle = name.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final p in [...builtInProfiles, ...homeGameProfiles]) {
      if (p.name.trim().toLowerCase() == needle) return p;
    }
    return null;
  }

  /// The resolved behavior model for the bot at [botIndex] (seat order, human
  /// excluded): its configured lineup spec, or the table default for seats past
  /// the lineup. Mirrors [_deciderForBot]'s resolution, used to name seats.
  BotSpec _specForSeat(int botIndex) {
    final seatBots = _effectiveSeatBots();
    return botIndex < seatBots.length
        ? seatBots[botIndex]
        : BotSpec(brain: config.botType, style: config.defaultStyle);
  }

  /// Names each bot seat after its persona (pro or distinctive archetype),
  /// numbering repeats ("Maniac 1", "Maniac 2"). Seats with no persona fall back
  /// to the generic name pool, in order.
  List<String> _seatNamesFor(List<BotSpec> specs) {
    final personaTotals = <String, int>{};
    for (final s in specs) {
      final n = s.personaName;
      if (n != null) personaTotals[n] = (personaTotals[n] ?? 0) + 1;
    }
    final personaSeen = <String, int>{};
    var poolIndex = 0;
    return [
      for (final s in specs)
        if (s.personaName case final base?)
          personaTotals[base]! > 1
              ? '$base ${personaSeen[base] = (personaSeen[base] ?? 0) + 1}'
              : base
        else
          TableConfig.botNamePool[poolIndex++ % TableConfig.botNamePool.length],
    ];
  }

  /// Builds the decider for the bot at [botIndex] (seat order, human excluded),
  /// recording its resolved behavior model for the seat badge. Bots past the
  /// configured lineup fall back to the table defaults.
  DecisionPolicy _deciderForBot(int botIndex, String playerId) {
    final override = config.deciderBuilder?.call(botIndex);
    if (override != null) {
      _specByPlayer[playerId] = BotSpec(brain: config.botType);
      return override;
    }
    final seatBots = _effectiveSeatBots();
    if (botIndex < seatBots.length) {
      final spec = seatBots[botIndex];
      _specByPlayer[playerId] = spec;
      final base = spec.profile;
      // Apply the offline auto-tuner's tuned baseline (amateurs only; pros are
      // never in the override map, so they keep their cached calibration).
      final pro = base == null
          ? null
          : (config.overrideProfile?.call(base) ?? base);
      if (pro != null) {
        // Amateurs get the degraded AmateurPolicy; pros get calibrated preflop
        // frequencies + the range-aware postflop brain. Shared with tournaments
        // via [deciderForProfile] so a personality plays identically everywhere.
        // Reads are bound to *this* bot's perspective (its read of the human is
        // only the hands it saw — see [OpponentStatsService.readsFor]).
        //
        // Deliberately NOT passing `tableCountProvider` here. A cash table is
        // always a single table, so it would always qualify for the same
        // search-backed postflop cutover the tournament final table gets —
        // tried, and reverted three times now. Two fixes landed along the
        // way and both measurably helped: giving the search the seat's real
        // `PersonalityProfile` (`PlayerProfile.toPersonalityProfile`), then
        // an explicit commitment-gate veto over the search's own pick
        // (`HeuristicPostflopEvaluator.commitOk`/`flushCommitOk`, reused
        // rather than duplicated) once it was clear the search alone
        // couldn't be trusted with that discipline at 500 iterations.
        // `deep_stack_discipline_test`'s bust rate is now fully within
        // bound (was 2.6x over). But `amateur_strength_test` still fails —
        // specific amateur/pro matchups still overshoot by ~100 bb/100
        // against a <4 bound (down from 150-160 before either fix, real
        // progress, just not enough) — and `postflop_discipline_test` still
        // can't gather enough small-bet-facing samples to judge. Revisit
        // once those are understood; likely candidates: rollout opponents
        // are still the generic `BotStrategy`, not the real seated
        // personalities, and 500 iterations may simply be too few for some
        // matchups.
        return deciderForProfile(
          pro,
          reads: _readsAs(playerId),
          mental: _mental,
        );
      }
      return buildDecider(
        spec.brain,
        profile: spec.style.profile,
        mctsIterations: config.mctsIterations,
      );
    }
    _specByPlayer[playerId] = BotSpec(
      brain: config.botType,
      style: config.defaultStyle,
    );
    return buildDecider(
      config.botType,
      profile: config.personality,
      mctsIterations: config.mctsIterations,
    );
  }

  @override
  Future<void> newGame() async {
    _createGame();
    await startNextHand();
  }

  @override
  Future<void> newGameWithBots(List<BotSpec> bots) async {
    _seatBots = List.of(bots);
    await newGame();
  }

  @override
  bool get buttonRotates => _rotateButton;

  @override
  void setButtonRotation(bool rotate) {
    if (rotate == _rotateButton) return;
    _rotateButton = rotate;
    // Rebuild the table so the change takes effect; history is preserved.
    _createGame();
    _publish();
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

    // Grade the decision *before* it is applied — the coach has to see the spot
    // the human actually faced. Skipped during batch evaluation, where there is
    // no human and the equity sims would dominate the run.
    if (!_evaluating && config.onEvalHandRecorded != null) {
      _recordDecision(game, current, action);
    }
    _applyAndRecord(current, action);
    _publish();
    await _runBots();
  }

  @override
  Future<void> simulate(int hands) async {
    if (_game == null) _createGame();
    final game = _game!;
    // Batch evaluation always tops stacks up each hand (see [_beginHand]), so a
    // long run measures win rate cleanly instead of stopping once someone busts.
    _evaluating = true;
    try {
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
    } finally {
      _evaluating = false;
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
      final spec = BotSpec(brain: config.botType, style: archetype);
      _specByPlayer[id] = spec;
      p.name = _freshBotName(spec.personaName);
      _deciders[id] = buildDecider(
        config.botType,
        profile: archetype.profile,
        mctsIterations: config.mctsIterations,
      );
    }
    _publish();
  }

  @override
  void replacePlayerWithProfile(String id, PlayerProfile profile) {
    final p = _playerById(id);
    // Between hands only: resetting the stack mid-hand would hand this seat
    // a fresh buy-in on top of whatever it's already put in the current pot,
    // conjuring chips out of nowhere. The UI already gates the icon on
    // `isHandOver`; this is the belt-and-braces backstop.
    if (p == null || p.isHuman || (_game != null && !_game!.isHandOver)) {
      return;
    }
    p.stack = config.startingStack;
    final spec = BotSpec(profile: profile);
    _specByPlayer[id] = spec;
    p.name = _freshBotName(profile.name);
    // Same resolution path used at initial seating (`_deciderForBot`), so a
    // profile seated mid-session plays identically to one dealt in from the
    // start — calibrated preflop + range-aware postflop for a pro, the
    // degraded `AmateurPolicy` for a recreational.
    _deciders[id] = deciderForProfile(
      config.overrideProfile?.call(profile) ?? profile,
      reads: _readsAs(id),
      mental: _mental,
    );
    _publish();
  }

  /// A table-unique name for a reseated bot: its [persona] name (numbering a
  /// collision, e.g. "Maniac 2"), or — when it has no persona — the first free
  /// name from the pool, falling back to a numbered guest.
  String _freshBotName([String? persona]) {
    final taken = {for (final p in _game?.players ?? const <Player>[]) p.name};
    if (persona != null) {
      if (!taken.contains(persona)) return persona;
      for (var i = 2; ; i++) {
        if (!taken.contains('$persona $i')) return '$persona $i';
      }
    }
    for (final name in TableConfig.botNamePool) {
      if (!taken.contains(name)) return name;
    }
    return 'Guest $_handCounter';
  }

}
