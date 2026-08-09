import 'dart:async';

import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/ai/ismcts.dart';
import 'package:monte/core/domain/ai/opponent_model.dart';
import 'package:monte/core/domain/ai/opponent_reads.dart';
import 'package:monte/core/domain/ai/player_read.dart';
import 'package:monte/core/domain/ai/player_stats.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/ai/profile_decider.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/core/domain/engine/player.dart';
import 'package:monte/core/domain/hand_history.dart';
import 'package:monte/features/reads/data/player_stats_store.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';
import 'package:monte/features/table/domain/game_repository.dart';
import 'package:monte/features/table/data/table_snapshot_projection.dart';
import 'package:monte/features/table/domain/table_config.dart';
import 'package:monte/features/table/domain/table_snapshot.dart';

/// Re-exported so the many existing `import '.../local_game_repository.dart'`
/// call sites (tests included) keep resolving [TableConfig] after it moved to
/// the domain layer where it belongs.
export 'package:monte/features/table/domain/table_config.dart';

/// Client-only implementation: the entire game runs on-device. Bots act
/// automatically with a short delay so the table feels alive. In all-bots mode
/// the engine plays itself, recording every hand for analysis.
class LocalGameRepository extends GameRepository {
  LocalGameRepository({this.config = const TableConfig(), this.statsService});

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
          name: botNames[i],
          stack: config.startingStack,
        ),
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

  /// The resolved behavior model for the bot at [botIndex] (seat order, human
  /// excluded): its configured lineup spec, or the table default for seats past
  /// the lineup. Mirrors [_deciderForBot]'s resolution, used to name seats.
  BotSpec _specForSeat(int botIndex) => botIndex < _seatBots.length
      ? _seatBots[botIndex]
      : BotSpec(brain: config.botType, style: config.defaultStyle);

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
    if (botIndex < _seatBots.length) {
      final spec = _seatBots[botIndex];
      _specByPlayer[playerId] = spec;
      final base = spec.profile;
      // Apply the offline auto-tuner's tuned baseline (amateurs only; pros are
      // never in the override map, so they keep their cached calibration).
      final pro = base == null ? null : (config.overrideProfile?.call(base) ?? base);
      if (pro != null) {
        // Amateurs get the degraded AmateurPolicy; pros get calibrated preflop
        // frequencies + the range-aware postflop brain. Shared with tournaments
        // via [deciderForProfile] so a personality plays identically everywhere.
        // Reads are bound to *this* bot's perspective (its read of the human is
        // only the hands it saw — see [OpponentStatsService.readsFor]).
        return deciderForProfile(pro, reads: _readsAs(playerId));
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

  /// Lets bots act with a short delay until it's the human's turn or the hand
  /// ends. In all-bots mode there's no human, so it plays the whole hand out;
  /// the next hand is dealt via [startNextHand] (or batched via [simulate]).
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

  // ---- Recording ------------------------------------------------------------

  /// Deals a fresh hand and starts a new history record. In evaluation mode
  /// stacks are topped back up so every hand is full and independent.
  void _beginHand() {
    final game = _game!;
    if (config.allBots || _evaluating) {
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

    // Record only the cards that were actually exposed: the human always knows
    // their own hand, and a live (non-folded) player who reached a showdown shows
    // — mirroring the live table reveal. Everyone else is masked. Safe: no stat
    // or opponent-model logic reads holeCards (only display does).
    final showdownHappened = game.results.any((r) => r.handValue != null);

    // Full-information tuning record — built from the *unmasked* data (all hole
    // cards, positions, model per seat) before masking below. Routed only to the
    // tuning store, never to a bot or the opponent model.
    if (config.onEvalHandRecorded != null) {
      config.onEvalHandRecorded!(_buildEvalHand(game));
    }

    final exposedPlayers = [
      for (final rec in _recPlayers)
        _exposeIfShown(rec, game, showdownHappened: showdownHappened),
    ];

    final hand = HandHistory(
      handNumber: _handCounter,
      smallBlind: game.smallBlind,
      bigBlind: game.bigBlind,
      players: exposedPlayers,
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
    );
    _history.add(hand);
    _opponentModel.observe(hand); // legacy in-session model (ISMCTS path)
    // Persistent per-opponent reads, keyed by stable identity (profile.id /
    // 'human'), for the exploitative pros — accumulated across sessions.
    if (!_evaluating) statsService?.record(hand, _identityOf);
    // Log interactive hands for diagnosis, but never the batch-sim flood.
    if (!_evaluating) config.onHandRecorded?.call(hand);
    _recPlayers = [];
    _recActions = [];
  }

  int _stackOf(String id) => _game!.players.firstWhere((p) => p.id == id).stack;

  /// Returns [rec] unchanged if its cards were exposed (human, or a non-folded
  /// player at a showdown), otherwise a masked copy (no cards, `revealed: false`).
  HandPlayer _exposeIfShown(
    HandPlayer rec,
    PokerGame game, {
    required bool showdownHappened,
  }) {
    final live = game.players.firstWhere((p) => p.id == rec.id);
    final exposed = live.isHuman || (showdownHappened && live.inHand);
    if (exposed) return rec;
    return HandPlayer(
      id: rec.id,
      name: rec.name,
      startingStack: rec.startingStack,
      holeCards: const [],
      isButton: rec.isButton,
      revealed: false,
    );
  }

  /// Builds the full-information [EvalHand] for the just-finished hand: every
  /// dealt player with their real hole cards, position, model, and (when a board
  /// ran out) made-hand rank. Reads only the live [game] + this hand's records —
  /// it does not touch the masked history or opponent model.
  EvalHand _buildEvalHand(PokerGame game) {
    final n = game.players.length;
    final board = game.board.map((c) => c.code).toList();
    final startingStackOf = {for (final r in _recPlayers) r.id: r.startingStack};

    final players = <EvalHandPlayer>[];
    for (final live in game.players) {
      if (!startingStackOf.containsKey(live.id)) continue; // not dealt in
      final offset = (game.players.indexOf(live) - game.buttonIndex + n) % n;
      final spec = _specByPlayer[live.id];
      final profile = spec?.profile;
      String? foldStreet;
      for (final a in _recActions) {
        if (a.playerId == live.id && a.type == ActionType.fold) {
          foldStreet = a.street.name;
          break;
        }
      }
      players.add(
        EvalHandPlayer(
          id: live.id,
          name: live.name,
          modelId: profile?.id ??
              (spec != null
                  ? '${spec.brain.name}:${spec.style.name}'
                  : 'human'),
          modelLabel: spec?.label ?? live.name,
          position: positionLabel(offset, n),
          seatsFromButton: offset,
          holeCards: live.hole.map((c) => c.code).toList(),
          startingStack: startingStackOf[live.id]!,
          finalStack: live.stack,
          folded: live.hasFolded,
          foldStreet: foldStreet,
          madeHand: game.board.length >= 3
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
      handNumber: _handCounter,
      smallBlind: game.smallBlind,
      bigBlind: game.bigBlind,
      players: players,
      actions: List.of(_recActions),
      board: board,
      results: [
        for (final r in game.results)
          HandResultRecord(
            playerId: r.player.id,
            amountWon: r.amountWon,
            handRank: r.handValue?.rank.label,
          ),
      ],
    );
  }

  // ---- Snapshot -------------------------------------------------------------

  void _publish() {
    _snapshot = _buildSnapshot();
    if (!_controller.isClosed) _controller.add(_snapshot);
  }

  TableSnapshot _buildSnapshot() => projectTableSnapshot(
        _game!,
        // In all-bots mode there's no human to protect, so reveal everyone.
        revealAll: config.allBots,
        behaviorLabels: {
          for (final e in _specByPlayer.entries) e.key: e.value.label,
        },
        // Colour each seat pro vs recreational, matching the tournament table.
        seatProfiles: {
          for (final e in _specByPlayer.entries)
            if (e.value.profile != null) e.key: e.value.profile!,
        },
        // Flag busted seats only in human-vs-bots play (all-bots tops up).
        flagBusted: !config.allBots,
      );
}
