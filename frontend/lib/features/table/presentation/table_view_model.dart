import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:monte/core/di/game_providers.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/features/table/domain/game_repository.dart';
import 'package:monte/features/table/domain/table_snapshot.dart';

/// Presentation ViewModel for the table: mirrors the repository's snapshot
/// stream into [state] and exposes the player's intents. The View talks only
/// to this, never to the repository directly.
class TableViewModel extends Notifier<TableSnapshot> {
  GameRepository get _repo => ref.read(gameRepositoryProvider);

  @override
  TableSnapshot build() {
    StreamSubscription<TableSnapshot>? sub;

    void bind(GameRepository repo) {
      sub?.cancel();
      sub = repo.watch().listen((snapshot) => state = snapshot);
      Future.microtask(repo.newGame);
    }

    // React to a repository swap (player count / bot settings change) WITHOUT
    // rebuilding this notifier synchronously: ref.listen + a deferred state
    // write keeps the change out of the widget build/flush window, which avoids
    // a "setState during build" on the startup settings-load race.
    ref.listen(gameRepositoryProvider, (_, next) {
      Future.microtask(() {
        state = next.snapshot;
        bind(next);
      });
    });
    ref.onDispose(() => sub?.cancel());

    bind(_repo);
    return _repo.snapshot;
  }

  bool get isAllBots => _repo.isAllBots;

  Future<void> submitAction(GameAction action) => _repo.submitAction(action);
  Future<void> newGame() => _repo.newGame();
  Future<void> startNextHand() => _repo.startNextHand();

  /// Refills a busted seat's bankroll, keeping the same player.
  void reloadPlayer(String id) => _repo.reloadPlayer(id);

  /// Replaces a busted bot with a fresh opponent of [archetype].
  void replacePlayer(String id, PersonalityArchetype archetype) =>
      _repo.replacePlayer(id, archetype);
}

final tableViewModelProvider = NotifierProvider<TableViewModel, TableSnapshot>(
  TableViewModel.new,
);
