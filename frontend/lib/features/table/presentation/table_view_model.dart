import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poker_client/core/di/game_providers.dart';
import 'package:poker_client/core/domain/engine/actions.dart';
import 'package:poker_client/features/table/domain/game_repository.dart';
import 'package:poker_client/features/table/domain/table_snapshot.dart';

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

final tableViewModelProvider = NotifierProvider<TableViewModel, TableSnapshot>(
  TableViewModel.new,
);
