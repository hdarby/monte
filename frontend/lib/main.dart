import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:monte/core/di/game_providers.dart';
import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/presentation/money_format.dart';
import 'package:monte/core/theme/app_theme.dart';
import 'package:monte/features/analytics/presentation/analytics_screen.dart';
import 'package:monte/features/settings/domain/game_settings.dart';
import 'package:monte/features/settings/presentation/settings_controller.dart';
import 'package:monte/features/settings/presentation/settings_screen.dart';
import 'package:monte/features/table/domain/table_snapshot.dart';
import 'package:monte/features/table/presentation/table_screen.dart';
import 'package:monte/features/table/presentation/table_view_model.dart';
import 'package:monte/features/table/presentation/widgets/bust_out_dialog.dart';
import 'package:monte/features/table/presentation/widgets/new_game_dialog.dart';

void main() => runApp(const ProviderScope(child: MonteApp()));

class MonteApp extends StatelessWidget {
  const MonteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monte',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const GamePage(),
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

  /// Whether the pre-game personality chooser has been shown for the current
  /// table. Reset when the table is rebuilt (player-count / mode change) so a
  /// fresh game always starts on the chooser.
  bool _startupPrompted = false;

  /// The last per-seat lineup chosen in the New Game dialog (bot-seat order),
  /// used to pre-fill it next time. Null until the player customizes once.
  List<BotSpec>? _seatBots;

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  void _openAnalytics() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AnalyticsScreen()));
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
  }

  /// On a freshly built table, open the personality chooser before play so the
  /// game always starts on the setup page. The default deal sits behind it and
  /// is replaced when the player confirms (or kept as-is if they cancel).
  void _maybePromptStartup(
    TableSnapshot snapshot,
    GameSettings settings,
    TableViewModel vm,
  ) {
    if (_startupPrompted || snapshot.seats.isEmpty) return;
    _startupPrompted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openNewGame(snapshot, settings, vm);
    });
  }

  /// Deals the next hand, guarded so a single space/enter or click can't trigger
  /// two deals. Reset once a hand is in progress (see [build]).
  void _dealNext(TableViewModel vm) {
    if (_nextHandPending) return;
    _nextHandPending = true;
    vm.startNextHand();
  }

  /// Space or Enter deals the next hand, but only between hands — during play
  /// these keys fall through to whatever has focus (e.g. action buttons).
  KeyEventResult _onKey(
    KeyEvent event,
    TableSnapshot snapshot,
    TableViewModel vm,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    final isDeal =
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter;
    if (!isDeal) return KeyEventResult.ignored;
    if (!snapshot.isHandOver || _bustDialogOpen) return KeyEventResult.ignored;
    _dealNext(vm);
    return KeyEventResult.handled;
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
  /// deal the next one after a short pause. Each completed hand rebuilds and
  /// re-arms this, so it loops until the toggle is switched off.
  void _maybeAutoDeal(TableSnapshot snapshot, TableViewModel vm) {
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
    // A new table (player-count / mode change) re-arms the startup chooser.
    ref.listen(gameRepositoryProvider, (_, _) => _startupPrompted = false);
    final settingsAsync = ref.watch(settingsControllerProvider);
    return settingsAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('Failed to load settings: $e'))),
      data: (settings) {
        final snapshot = ref.watch(tableViewModelProvider);
        final vm = ref.read(tableViewModelProvider.notifier);
        // A hand is dealing/in progress again — re-arm the deal guard.
        if (!snapshot.isHandOver) _nextHandPending = false;
        _maybePromptStartup(snapshot, settings, vm);
        _maybePromptBust(snapshot, vm);
        _maybeAutoDeal(snapshot, vm);
        return MoneyScope(
          format: MoneyFormat(showBigBlinds: settings.showBigBlinds),
          child: Focus(
            autofocus: true,
            onKeyEvent: (_, event) => _onKey(event, snapshot, vm),
            child: TableScreen(
              snapshot: snapshot,
              isAllBots: vm.isAllBots,
              playerCount: settings.playerCount,
              showBehavior: settings.showBehavior,
              onAction: vm.submitAction,
              onNewGame: () => _openNewGame(snapshot, settings, vm),
              onNextHand: () => _dealNext(vm),
              onOpenSettings: _openSettings,
              onOpenAnalytics: _openAnalytics,
              autoDeal: _autoDeal,
              onToggleAutoDeal: (v) => setState(() => _autoDeal = v),
            ),
          ),
        );
      },
    );
  }
}
