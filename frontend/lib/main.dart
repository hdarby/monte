import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:monte/core/presentation/money_format.dart';
import 'package:monte/core/theme/app_theme.dart';
import 'package:monte/features/analytics/presentation/analytics_screen.dart';
import 'package:monte/features/settings/presentation/settings_controller.dart';
import 'package:monte/features/settings/presentation/settings_screen.dart';
import 'package:monte/features/table/presentation/table_screen.dart';
import 'package:monte/features/table/presentation/table_view_model.dart';

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
class GamePage extends ConsumerWidget {
  const GamePage({super.key});

  void _openSettings(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  void _openAnalytics(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AnalyticsScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsControllerProvider);
    return settingsAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('Failed to load settings: $e'))),
      data: (settings) {
        final snapshot = ref.watch(tableViewModelProvider);
        final vm = ref.read(tableViewModelProvider.notifier);
        return MoneyScope(
          format: MoneyFormat(showBigBlinds: settings.showBigBlinds),
          child: TableScreen(
            snapshot: snapshot,
            isAllBots: vm.isAllBots,
            playerCount: settings.playerCount,
            onAction: vm.submitAction,
            onNewGame: vm.newGame,
            onNextHand: vm.startNextHand,
            onOpenSettings: () => _openSettings(context),
            onOpenAnalytics: () => _openAnalytics(context),
          ),
        );
      },
    );
  }
}
