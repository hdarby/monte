import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:monte/core/di/game_providers.dart';
import 'package:monte/features/tournament/data/tournament_save_store.dart';
import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/features/reads/data/player_stats_store.dart';
import 'package:monte/features/table/data/local_game_repository.dart';
import 'package:monte/core/presentation/money_format.dart';
import 'package:monte/core/presentation/widgets/table_loading_view.dart';
import 'package:monte/features/coach/domain/hand_coach.dart';
import 'package:monte/features/coach/presentation/coach_screen.dart';
import 'package:monte/core/theme/app_theme.dart';
import 'package:monte/features/history/presentation/history_screen.dart';
import 'package:monte/features/landing/presentation/landing_screen.dart';
import 'package:monte/features/tournament/presentation/career_screen.dart';
import 'package:monte/features/tournament/presentation/lobby_screen.dart';
import 'package:monte/features/settings/domain/game_settings.dart';
import 'package:monte/features/settings/presentation/settings_controller.dart';
import 'package:monte/features/settings/presentation/settings_screen.dart';
import 'package:monte/features/table/domain/table_snapshot.dart';
import 'package:monte/features/table/presentation/table_screen.dart';
import 'package:monte/features/table/presentation/table_view_model.dart';
import 'package:monte/features/table/presentation/widgets/bust_out_dialog.dart';
import 'package:monte/features/eval_history/data/file_eval_history_store.dart';
import 'package:monte/features/tournament/data/tournament_result_store.dart';
import 'package:monte/features/eval_history/presentation/auto_tune_job.dart';
import 'package:monte/features/eval_history/presentation/eval_history_provider.dart';
import 'package:monte/features/table/presentation/widgets/new_game_dialog.dart';
import 'package:monte/features/table/presentation/widgets/change_player_dialog.dart';

/// Bumped whenever a change (e.g. a hand-evaluation fix) invalidates
/// previously-learned tuning. On a mismatch, [_resetStaleTuning] wipes the
/// persisted overrides and the eval-history sample so tuning starts clean.
const _tuningVersion = 2;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Resolve the permanent tuning-history location once, up front, so the store
  // can append synchronously as hands complete.
  final dir = await getApplicationSupportDirectory();
  final store = FileEvalHistoryStore(dir);
  // Discard tuning learned against superseded evaluation logic (one-time, gated
  // on [_tuningVersion]) so stale overrides can't skew play after an engine fix.
  await _resetStaleTuning(store);
  // Persistent per-opponent reads (VPIP/PFR/3-bet/steal/etc.), loaded once so
  // exploitative pros carry their reads across sessions and events.
  final statsService = await OpponentStatsService.load(
    FilePlayerStatsStore(dir),
  );
  // Own the container explicitly so the background auto-tune job can be started
  // here (in the real entrypoint only — widget tests pump `MonteApp` directly
  // and never start its timer).
  final container = ProviderContainer(
    overrides: [
      evalHistoryStoreProvider.overrideWithValue(store),
      tournamentResultStoreProvider.overrideWithValue(
        FileTournamentResultStore(dir),
      ),
      opponentStatsServiceProvider.overrideWithValue(statsService),
      tournamentSaveStoreProvider.overrideWithValue(
        FileTournamentSaveStore(dir),
      ),
    ],
  );
  // Seed the human's name from the last session so the UI can address them by
  // name (and so a changed name can trigger a reads wipe on first prompt).
  final savedName = (await SharedPreferences.getInstance()).getString(
    'player_name',
  );
  if (savedName != null && savedName.trim().isNotEmpty) {
    container.read(playerNameProvider.notifier).set(savedName);
  }
  container.read(autoTuneJobProvider.notifier).start();
  runApp(
    UncontrolledProviderScope(container: container, child: const MonteApp()),
  );
}

/// When the stored tuning version differs from [_tuningVersion], clears the
/// persisted profile overrides and wipes the eval-history file, then records the
/// new version. A no-op once the versions match.
Future<void> _resetStaleTuning(FileEvalHistoryStore store) async {
  const versionKey = 'tuning_version';
  const overridesKey = 'profile_overrides';
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getInt(versionKey) == _tuningVersion) return;
    await prefs.remove(overridesKey);
    await store.wipe();
    await prefs.setInt(versionKey, _tuningVersion);
  } catch (_) {
    // No prefs/store available (e.g. headless) — nothing to reset.
  }
}

class MonteApp extends StatelessWidget {
  const MonteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monte',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const AppLandingPage(),
    );
  }
}

/// The app's entry point: [LandingScreen] routes to a cash game, the
/// tournament lobby, or settings.
class AppLandingPage extends ConsumerWidget {
  const AppLandingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LandingScreen(
      onCashGames: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const GamePage()));
      },
      onTournaments: () {
        final name = ref.read(playerNameProvider);
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => LobbyScreen(humanName: name)));
      },
      onOptions: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
      },
    );
  }
}

/// Hosts the table. Reads settings + the table ViewModel from Riverpod and
/// wires the View's intents to the ViewModel.
class GamePage extends ConsumerStatefulWidget {
  const GamePage({super.key});

  @override
  ConsumerState<GamePage> createState() => _GamePageState();
}

class _GamePageState extends ConsumerState<GamePage> {
  /// Guards against stacking multiple bust-out dialogs.
  bool _bustDialogOpen = false;

  /// All-bots: keep dealing hands until switched off.
  bool _autoDeal = false;
  bool _autoDealScheduled = false;

  /// Guards a "deal next hand" from firing twice for one key press / click.
  bool _nextHandPending = false;

  /// Whether the very first hand of this session has reached a point the
  /// player can actually engage with (their turn, or the hand already over).
  /// Until then, bots may still be acting through their pre-turn seats with a
  /// real per-action delay (see `LocalGameRepository._runBots`) — that's the
  /// stretch the loading animation covers. Sticky once true: later hands'
  /// identical bots-acting-first stretches are the normal "watch them play"
  /// experience, not something to hide behind a loading screen every time.
  bool _tableSettled = false;

  /// The last per-seat lineup chosen in the New Game dialog (bot-seat order),
  /// used to pre-fill it next time. Null until the player customizes once.
  List<BotSpec>? _seatBots;

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  void _openHistory() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const HistoryScreen()));
  }

  void _openTournament() {
    final name = ref.read(playerNameProvider);
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => LobbyScreen(humanName: name)));
  }

  void _openCareer() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CareerScreen()));
  }

  /// Opens the in-hand coach for the human, computing the read once from the
  /// current [snapshot]. Models only opponents still in the hand who've put
  /// chips in (those "yet to act" reveal no range).
  void _openCoach(
    TableSnapshot snapshot,
    GameSettings settings,
    TableViewModel vm,
  ) {
    final report = _coachReport(snapshot, settings);
    if (report == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CoachScreen(
          report: report,
          money: MoneyFormat(
            showBigBlinds: settings.showBigBlinds,
            bigBlind: settings.bigBlind,
          ),
          // On the human's turn, each suggestion is playable: tapping it submits
          // that action as the human's move and returns to the table.
          onAction: snapshot.isHumanTurn ? vm.submitAction : null,
        ),
      ),
    );
  }

  /// Builds the coach read from the current [snapshot], or null if there's no
  /// human seat. Models only opponents still in the hand who've put chips in
  /// (those "yet to act" reveal no range).
  CoachReport? _coachReport(TableSnapshot snapshot, GameSettings settings) {
    final human = snapshot.human;
    if (human == null) return null;
    final ctx = snapshot.actionContext;
    final live = snapshot.seats.where((s) => !s.isHuman && !s.folded).toList();
    // Who's actually in with a range: opponents who've voluntarily raised or
    // matched the going bet. This deliberately excludes the blinds when they're
    // still short of the current bet (posting a blind isn't a range — counting
    // them as extra opponents wrecks the multiway equity read).
    final goingBet =
        ctx?.currentBet ??
        live.fold<int>(0, (m, s) => math.max(m, s.currentBet));
    final committed = live
        .where(
          (s) => s.raiseLevel > 0 || (goingBet > 0 && s.currentBet >= goingBet),
        )
        .toList();
    final acted = committed.isNotEmpty
        ? committed
        : live.where((s) => s.currentBet > 0).toList();
    final modeled = acted.isNotEmpty ? acted : live;
    final effStack = live.isEmpty
        ? human.stack
        : math.min(human.stack, live.map((s) => s.stack).reduce(math.max));
    // raiseCount is only on ActionContext (hero's turn); off-turn fall back to
    // the loudest seat's raise level so the range read still reflects aggression.
    final raiseCount =
        ctx?.raiseCount ??
        snapshot.seats.fold<int>(0, (m, s) => math.max(m, s.raiseLevel));

    return HandCoach.analyze(
      HandCoachInput(
        hole: human.holeCards ?? const [],
        board: snapshot.board,
        pot: snapshot.pot,
        toCall: ctx?.callAmount ?? 0,
        heroCurrentBet: human.currentBet,
        currentBet: ctx?.currentBet ?? 0,
        effectiveStack: effStack,
        bigBlind: settings.bigBlind,
        street: snapshot.round,
        raiseCount: raiseCount,
        opponents: modeled.length,
        opponentLabels: [for (final s in modeled) s.name],
        canCheck: ctx?.canCheck ?? false,
        canRaise: ctx?.canRaise ?? false,
        minRaiseTo: ctx?.minRaiseTo ?? 0,
        maxRaiseTo: ctx?.maxRaiseTo ?? 0,
        random: math.Random(),
      ),
      analysisAvailable: snapshot.isHumanTurn,
    );
  }

  /// Opens the pre-game setup so the player can set each bot seat's playing
  /// style, then deals a fresh game with that lineup. Seats and their names come
  /// from the current table (human excluded), in bot-seat order.
  Future<void> _openNewGame(
    TableSnapshot snapshot,
    GameSettings settings,
    TableViewModel vm,
  ) async {
    final botSeats = snapshot.seats.where((s) => !s.isHuman).toList();
    final names = [for (final s in botSeats) s.name];
    final last = _seatBots;
    // Default each seat to a personality-driven brain so styles are immediately
    // selectable and visible. (The Heuristic brain ignores personality, so we
    // don't want it as the out-of-the-box default here.) An explicit global
    // choice of Personality or MCTS is respected.
    final defaultBrain = settings.botType.usesPersonality
        ? settings.botType
        : BotType.personality;
    final fallback = BotSpec(
      brain: defaultBrain,
      style: settings.botPersonality,
    );
    final initial = [
      for (var i = 0; i < botSeats.length; i++)
        (last != null && i < last.length) ? last[i] : fallback,
    ];

    final chosen = await showNewGameDialog(
      context,
      seatNames: names,
      initial: initial,
    );
    if (chosen == null) return; // cancelled
    setState(() => _seatBots = chosen);
    await vm.newGameWithBots(chosen);
    _persistSeatBots(vm);
  }

  /// Opens the pro/amateur picker for one bot seat and, if the player chooses
  /// someone, reseats that bot with the picked profile. Excludes whoever is
  /// already seated so the same player can't sit at the table twice.
  Future<void> _openChangePlayer(
    TableSnapshot snapshot,
    TableViewModel vm,
    String seatId,
  ) async {
    final seated = {for (final s in snapshot.seats) s.profileId};
    final profile = await showChangePlayerDialog(
      context,
      seatedProfileIds: seated,
    );
    if (profile == null) return;
    vm.replacePlayerWithProfile(seatId, profile);
    _persistSeatBots(vm);
  }

  /// Saves the table's current lineup into settings, so the same players are
  /// still there the next time the table is built — leaving for the landing
  /// screen and coming back, or relaunching the app, both rebuild the table
  /// from persisted `GameSettings`, which otherwise still held whatever
  /// lineup was last saved from the New Game/Settings dialogs, not whatever
  /// was actually live (a fresh deal, or an individual reseat).
  void _persistSeatBots(TableViewModel vm) {
    final settings = ref.read(settingsControllerProvider).value;
    if (settings == null) return;
    ref
        .read(settingsControllerProvider.notifier)
        .save(settings.copyWith(seatBots: vm.currentSeatBots));
  }

  /// Deals the next hand, guarded so a single space/enter or click can't trigger
  /// two deals. Reset once a hand is in progress (see [build]).
  Future<void> _dealNext(TableViewModel vm, GameSettings settings) async {
    if (_nextHandPending) return;
    _nextHandPending = true;
    await vm.startNextHand();
    if (mounted) {
      _nextHandPending = false;
    }
  }

  /// Space or Enter is the "default action" key. Between hands it deals the next
  /// one; on the human's turn it plays the coach's recommended action; otherwise
  /// it falls through to whatever has focus (e.g. action buttons).
  KeyEventResult _onKey(
    KeyEvent event,
    TableSnapshot snapshot,
    GameSettings settings,
    TableViewModel vm,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    final isDefault =
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter;
    if (!isDefault) return KeyEventResult.ignored;
    if (_bustDialogOpen) return KeyEventResult.ignored;
    if (snapshot.isHandOver) {
      _dealNext(vm, settings);
      return KeyEventResult.handled;
    }
    // Mid-hand: on the human's turn, play the coach's recommendation.
    if (snapshot.isHumanTurn) {
      final report = _coachReport(snapshot, settings);
      final i = report?.recommendedIndex ?? -1;
      if (report != null && i >= 0 && i < report.actions.length) {
        vm.submitAction(report.actions[i].toGameAction());
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// When a hand ends with busted seats, prompt the player to resolve the first
  /// one (reload or replace). Resolving publishes a new snapshot, which brings
  /// us back here for the next busted seat until none remain.
  void _maybePromptBust(TableSnapshot snapshot, TableViewModel vm) {
    if (_bustDialogOpen ||
        !snapshot.isHandOver ||
        snapshot.bustedPlayerIds.isEmpty) {
      return;
    }
    final id = snapshot.bustedPlayerIds.first;
    final matches = snapshot.seats.where((s) => s.id == id);
    if (matches.isEmpty) return;
    final seat = matches.first;

    _bustDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await showBustOutDialog(
        context,
        seat: seat,
        onReload: () => vm.reloadPlayer(id),
        onReplace: (archetype) => vm.replacePlayer(id, archetype),
      );
      _bustDialogOpen = false;
      if (mounted) setState(() {}); // re-check for any remaining busted seats
    });
  }

  /// In all-bots mode, when auto-deal is on and the current hand has finished,
  /// deal the next one after a short pause for UI responsiveness.
  void _maybeAutoDeal(
    TableSnapshot snapshot,
    TableViewModel vm,
    GameSettings settings,
  ) {
    if (!_autoDeal ||
        !vm.isAllBots ||
        !snapshot.isHandOver ||
        _autoDealScheduled) {
      return;
    }
    _autoDealScheduled = true;
    Future.delayed(const Duration(milliseconds: 700), () async {
      _autoDealScheduled = false;
      if (!mounted || !_autoDeal) return;
      await vm.startNextHand();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsControllerProvider);
    return settingsAsync.when(
      loading: () => const TableLoadingView(),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('Failed to load settings: $e'))),
      data: (settings) {
        final snapshot = ref.watch(tableViewModelProvider);
        final vm = ref.read(tableViewModelProvider.notifier);
        // Cover the real, visible stretch at the start of a session where
        // seats haven't been dealt into yet, or bots are still acting through
        // their seats before the player's first turn (each with a genuine
        // pace-of-play delay) — everything up to that point can't be acted
        // on anyway. All-bots mode has no "player's turn" to wait for, so it
        // skips straight to watching the table.
        if (!vm.isAllBots && !_tableSettled) {
          if (snapshot.seats.isNotEmpty &&
              (snapshot.isHumanTurn || snapshot.isHandOver)) {
            _tableSettled = true;
          } else {
            return const TableLoadingView();
          }
        }
        // A hand is dealing/in progress again — re-arm the deal guard.
        if (!snapshot.isHandOver) _nextHandPending = false;
        _maybePromptBust(snapshot, vm);
        _maybeAutoDeal(snapshot, vm, settings);
        return MoneyScope(
          format: MoneyFormat(
            showBigBlinds: settings.showBigBlinds,
            bigBlind: settings.bigBlind,
          ),
          child: Focus(
            autofocus: true,
            onKeyEvent: (_, event) => _onKey(event, snapshot, settings, vm),
            child: TableScreen(
              snapshot: snapshot,
              isAllBots: vm.isAllBots,
              humanName: ref.watch(playerNameProvider),
              playerCount: settings.playerCount,
              showBehavior: settings.showBehavior,
              animateCardDeal: settings.animateCardDeal,
              onAction: vm.submitAction,
              onNewGame: () => _openNewGame(snapshot, settings, vm),
              onNextHand: () => _dealNext(vm, settings),
              onOpenSettings: _openSettings,
              onOpenHistory: _openHistory,
              onOpenTournament: _openTournament,
              onOpenCareer: _openCareer,
              onCoach: () => _openCoach(snapshot, settings, vm),
              autoDeal: _autoDeal,
              onToggleAutoDeal: (v) => setState(() => _autoDeal = v),
              // Cash game with a human seat: tap an opponent to read their range.
              showOpponentRanges: !vm.isAllBots,
              // Hover any seat to see the accumulated read on that player.
              readForSeat: vm.isAllBots
                  ? null
                  : (id) {
                      final repo = ref.read(gameRepositoryProvider);
                      return repo is LocalGameRepository
                          ? repo.readForSeat(id)
                          : null;
                    },
              onChangePlayer: (id) => _openChangePlayer(snapshot, vm, id),
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
        );
      },
    );
  }
}
