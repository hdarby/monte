import 'package:flutter/material.dart';

import 'data/game_repository.dart';
import 'data/local_game_repository.dart';
import 'settings/game_settings.dart';
import 'settings/settings_store.dart';
import 'theme/app_theme.dart';
import 'ui/money_format.dart';
import 'ui/screens/analytics_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/table_screen.dart';

void main() => runApp(const PokerApp());

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

/// Owns the [GameRepository] and the persisted [GameSettings] for the session.
///
/// Swap [LocalGameRepository] for a future `RemoteGameRepository` here and the
/// rest of the app is unchanged.
class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  final SettingsStore _store = SettingsStore();

  GameSettings? _settings;
  TableConfig _config = const TableConfig();
  GameRepository? _repository;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  TableConfig _configFor(GameSettings settings) => TableConfig(
        playerCount: settings.playerCount,
        allBots: settings.allBots,
        // Bots play faster when watching an all-bots evaluation table.
        botThinkTime: settings.allBots
            ? const Duration(milliseconds: 250)
            : const Duration(milliseconds: 700),
      );

  Future<void> _bootstrap() async {
    final settings = await _store.load();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _config = _configFor(settings);
      _repository = LocalGameRepository(config: _config);
    });
    await _repository!.newGame();
  }

  void _openAnalytics() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnalyticsScreen(repository: _repository!),
      ),
    );
  }

  Future<void> _openSettings() async {
    final updated = await Navigator.of(context).push<GameSettings>(
      MaterialPageRoute(builder: (_) => SettingsScreen(settings: _settings!)),
    );
    if (updated == null || !mounted) return;

    await _store.save(updated);
    // A player-count or all-bots change needs a fresh game; display units
    // update live without restarting.
    final restart = updated.playerCount != _settings!.playerCount ||
        updated.allBots != _settings!.allBots;
    final old = _repository;
    setState(() {
      _settings = updated;
      if (restart) {
        _config = _configFor(updated);
        _repository = LocalGameRepository(config: _config);
      }
    });
    if (restart) {
      old?.dispose();
      await _repository!.newGame();
    }
  }

  @override
  void dispose() {
    _repository?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final repository = _repository;
    if (settings == null || repository == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return MoneyScope(
      format: MoneyFormat(
        showBigBlinds: settings.showBigBlinds,
        bigBlind: _config.bigBlind,
      ),
      child: ListenableBuilder(
        listenable: repository,
        builder: (context, _) => TableScreen(
          snapshot: repository.snapshot,
          repository: repository,
          playerCount: settings.playerCount,
          onOpenSettings: _openSettings,
          onOpenAnalytics: _openAnalytics,
        ),
      ),
    );
  }
}
