import 'package:flutter/material.dart';

import 'data/game_repository.dart';
import 'data/local_game_repository.dart';
import 'theme/app_theme.dart';
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

/// Owns the [GameRepository] for the session.
///
/// Swap [LocalGameRepository] for a future `RemoteGameRepository` here and the
/// rest of the app is unchanged.
class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  late final GameRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository = LocalGameRepository();
    _repository.newGame();
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
      ),
    );
  }
}
