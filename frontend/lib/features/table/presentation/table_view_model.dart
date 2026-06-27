import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poker_client/core/domain/engine/actions.dart';
import 'package:poker_client/features/settings/presentation/settings_controller.dart';
import 'package:poker_client/features/table/data/local_game_repository.dart';
import 'package:poker_client/features/table/domain/game_repository.dart';
import 'package:poker_client/features/table/domain/table_snapshot.dart';

/// Builds the [GameRepository] for the current table shape. Rebuilds (disposing
/// the old repository) only when the player count or all-bots mode changes —
/// display-unit changes don't restart the game.
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

/// Presentation ViewModel for the table: mirrors the repository's snapshot
/// stream into [state] and exposes the player's intents. The View talks only
/// to this, never to the repository directly.
class TableViewModel extends Notifier<TableSnapshot> {
  GameRepository get _repo => ref.read(gameRepositoryProvider);

  @override
  TableSnapshot build() {
    final repo = ref.watch(gameRepositoryProvider);
    final sub = repo.watch().listen((snapshot) => state = snapshot);
    ref.onDispose(sub.cancel);
    // Kick off the first hand once the subscription is in place.
    Future.microtask(repo.newGame);
    return repo.snapshot;
  }

  bool get isAllBots => _repo.isAllBots;

  Future<void> submitAction(GameAction action) => _repo.submitAction(action);
  Future<void> newGame() => _repo.newGame();
  Future<void> startNextHand() => _repo.startNextHand();
}

final tableViewModelProvider =
    NotifierProvider<TableViewModel, TableSnapshot>(TableViewModel.new);
