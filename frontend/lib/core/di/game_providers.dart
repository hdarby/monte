import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:monte/features/settings/domain/game_settings.dart';
import 'package:monte/features/settings/presentation/settings_controller.dart';
import 'package:monte/features/table/data/local_game_repository.dart';
import 'package:monte/features/table/domain/game_repository.dart';

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
  // Select only the fields that define the game itself, so a display-unit
  // toggle (dollars vs BB) doesn't restart the game.
  final (playerCount, allBots, botType, botPersonality) = ref.watch(
    settingsControllerProvider.select((s) {
      final v = s.value ?? const GameSettings();
      return (v.playerCount, v.allBots, v.botType, v.botPersonality);
    }),
  );
  final repo = LocalGameRepository(
    config: TableConfig(
      playerCount: playerCount,
      allBots: allBots,
      botType: botType,
      personality: botPersonality.profile,
      botThinkTime: allBots
          ? const Duration(milliseconds: 250)
          : const Duration(milliseconds: 700),
    ),
  );
  ref.onDispose(repo.dispose);
  return repo;
});
