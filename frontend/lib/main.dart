import 'package:flutter/material.dart';

import 'data/game_repository.dart';
import 'data/local_game_repository.dart';
import 'theme/app_theme.dart';
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

/// Owns the [GameRepository] and table configuration for the session.
///
/// Swap [LocalGameRepository] for a future `RemoteGameRepository` here and the
/// rest of the app is unchanged.
class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  int _playerCount = 4;
  late GameRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository = _buildRepository();
    _repository.newGame();
  }

  GameRepository _buildRepository() =>
      LocalGameRepository(config: TableConfig(playerCount: _playerCount));

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(playerCount: _playerCount),
      ),
    );
    if (result == null || !mounted) return;

    // Apply the new table size by starting a fresh game.
    final old = _repository;
    setState(() {
      _playerCount = result;
      _repository = _buildRepository();
    });
    old.dispose();
    await _repository.newGame();
  }

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repository,
      builder: (context, _) => TableScreen(
        snapshot: _repository.snapshot,
        repository: _repository,
        playerCount: _playerCount,
        onOpenSettings: _openSettings,
      ),
    );
  }
}
