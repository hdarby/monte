import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poker_client/core/presentation/money_format.dart';
import 'package:poker_client/core/theme/app_theme.dart';
import 'package:poker_client/features/analytics/presentation/analytics_screen.dart';
import 'package:poker_client/features/settings/domain/game_settings.dart';
import 'package:poker_client/features/settings/presentation/settings_controller.dart';
import 'package:poker_client/features/settings/presentation/settings_screen.dart';
import 'package:poker_client/features/table/data/local_game_repository.dart';
import 'package:poker_client/features/table/domain/game_repository.dart';
import 'package:poker_client/features/table/presentation/table_screen.dart';

void main() => runApp(const ProviderScope(child: PokerApp()));

class PokerApp extends StatelessWidget {
  const PokerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Poker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const GamePage(),
    );
  }
}

/// Hosts the table. Settings come from [settingsControllerProvider]; the game
/// repository is (re)built when the table size or all-bots mode changes.
///
/// NOTE: the game/table itself migrates to a ViewModel in the next step — for
/// now this owns the [LocalGameRepository] lifecycle directly.
class GamePage extends ConsumerStatefulWidget {
  const GamePage({super.key});

  @override
  ConsumerState<GamePage> createState() => _GamePageState();
}

class _GamePageState extends ConsumerState<GamePage> {
  GameRepository? _repository;
  TableConfig _config = const TableConfig();

  TableConfig _configFor(GameSettings s) => TableConfig(
        playerCount: s.playerCount,
        allBots: s.allBots,
        // Bots play faster when watching an all-bots evaluation table.
        botThinkTime: s.allBots
            ? const Duration(milliseconds: 250)
            : const Duration(milliseconds: 700),
      );

  /// Rebuilds the game only when the table shape changes (player count / all
  /// bots). Display-unit changes are handled live by [MoneyScope].
  void _applySettings(GameSettings s) {
    final needsNewGame = _repository == null ||
        s.playerCount != _config.playerCount ||
        s.allBots != _config.allBots;
    if (!needsNewGame) return;

    final old = _repository;
    final config = _configFor(s);
    final repo = LocalGameRepository(config: config);
    setState(() {
      _config = config;
      _repository = repo;
    });
    old?.dispose();
    repo.newGame();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _openAnalytics() {
    final repo = _repository;
    if (repo == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AnalyticsScreen(repository: repo)),
    );
  }

  @override
  void dispose() {
    _repository?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsControllerProvider, (_, next) {
      next.whenData(_applySettings);
    });

    final settingsAsync = ref.watch(settingsControllerProvider);
    return settingsAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Failed to load settings: $e')),
      ),
      data: (settings) {
        final repo = _repository;
        if (repo == null) {
          // First settings emission triggers _applySettings via the listener.
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return MoneyScope(
          format: MoneyFormat(
            showBigBlinds: settings.showBigBlinds,
            bigBlind: _config.bigBlind,
          ),
          child: ListenableBuilder(
            listenable: repo,
            builder: (context, _) => TableScreen(
              snapshot: repo.snapshot,
              repository: repo,
              playerCount: settings.playerCount,
              onOpenSettings: _openSettings,
              onOpenAnalytics: _openAnalytics,
            ),
          ),
        );
      },
    );
  }
}
