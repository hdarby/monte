import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poker_client/features/settings/presentation/settings_controller.dart';
import 'package:poker_client/features/table/data/local_game_repository.dart';
import 'package:poker_client/features/table/domain/game_repository.dart';

/// Composition root for the game.
///
/// Binds [GameRepository] to a concrete implementation, built from the current
/// settings. Rebuilds (disposing the old repository) only when the player count
/// or all-bots mode changes — display-unit changes don't restart the game.
///
/// This is the single place that picks the implementation: to move to
/// client/server, swap [LocalGameRepository] for a `RemoteGameRepository` here
/// and nothing else in the app changes.
final gameRepositoryProvider = Provider<GameRepository>((ref) {
  final (playerCount, allBots) = ref.watch(
    settingsControllerProvider.select(
      (s) => (s.value?.playerCount ?? 4, s.value?.allBots ?? false),
    ),
  );
  final repo = LocalGameRepository(
    config: TableConfig(
      playerCount: playerCount,
      allBots: allBots,
      botThinkTime: allBots
          ? const Duration(milliseconds: 250)
          : const Duration(milliseconds: 700),
    ),
  );
  ref.onDispose(repo.dispose);
  return repo;
});
