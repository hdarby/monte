import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:monte/core/di/game_providers.dart';
import 'package:monte/core/domain/hand_history.dart';
import 'package:monte/features/table/domain/game_repository.dart';

/// Immutable hand-history view state: recorded hands, newest first.
class HistoryState {
  const HistoryState({required this.hands});

  /// Hands most-recent first (the order a reviewer wants).
  final List<HandHistory> hands;

  bool get isEmpty => hands.isEmpty;
}

/// Exposes the repository's recorded hand histories (newest first) for the
/// review screen, refreshing whenever the table emits (a hand ended, a batch
/// finished, or history was cleared).
class HistoryViewModel extends Notifier<HistoryState> {
  GameRepository get _repo => ref.read(gameRepositoryProvider);

  @override
  HistoryState build() {
    final repo = ref.watch(gameRepositoryProvider);
    final sub = repo.watch().listen((_) => state = _compute());
    ref.onDispose(sub.cancel);
    return _compute();
  }

  HistoryState _compute() =>
      HistoryState(hands: _repo.history.reversed.toList(growable: false));
}

final historyViewModelProvider =
    NotifierProvider<HistoryViewModel, HistoryState>(HistoryViewModel.new);
