import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:monte/core/presentation/money_format.dart';
import 'package:monte/core/theme/app_theme.dart';
import 'package:monte/features/analytics/presentation/analytics_screen.dart';
import 'package:monte/features/settings/presentation/settings_controller.dart';
import 'package:monte/features/settings/presentation/settings_screen.dart';
import 'package:monte/features/table/domain/table_snapshot.dart';
import 'package:monte/features/table/presentation/table_screen.dart';
import 'package:monte/features/table/presentation/table_view_model.dart';
import 'package:monte/features/table/presentation/widgets/bust_out_dialog.dart';

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
    final settingsAsync = ref.watch(settingsControllerProvider);
    return settingsAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('Failed to load settings: $e'))),
      data: (settings) {
        final snapshot = ref.watch(tableViewModelProvider);
        final vm = ref.read(tableViewModelProvider.notifier);
        _maybePromptBust(snapshot, vm);
        _maybeAutoDeal(snapshot, vm);
        return MoneyScope(
          format: MoneyFormat(showBigBlinds: settings.showBigBlinds),
          child: TableScreen(
            snapshot: snapshot,
            isAllBots: vm.isAllBots,
            playerCount: settings.playerCount,
            onAction: vm.submitAction,
            onNewGame: vm.newGame,
            onNextHand: vm.startNextHand,
            onOpenSettings: _openSettings,
            onOpenAnalytics: _openAnalytics,
            autoDeal: _autoDeal,
            onToggleAutoDeal: (v) => setState(() => _autoDeal = v),
          ),
        );
      },
    );
  }
}
