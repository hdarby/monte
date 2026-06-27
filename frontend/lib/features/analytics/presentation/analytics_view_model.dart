import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poker_client/core/di/game_providers.dart';
import 'package:poker_client/features/analytics/domain/analytics.dart';
import 'package:poker_client/features/table/domain/game_repository.dart';

/// Immutable analytics view state.
class AnalyticsState {
  const AnalyticsState({required this.stats, required this.handCount});

  final List<PlayerStats> stats;
  final int handCount;
}

/// Computes [PlayerStats] from the game repository's recorded hand histories,
/// recomputing whenever the table emits (a hand played, a simulation finished).
class AnalyticsViewModel extends Notifier<AnalyticsState> {
  GameRepository get _repo => ref.read(gameRepositoryProvider);

  @override
  AnalyticsState build() {
    final repo = ref.watch(gameRepositoryProvider);
    final sub = repo.watch().listen((_) => state = _compute());
    ref.onDispose(sub.cancel);
    return _compute();
  }

  AnalyticsState _compute() => AnalyticsState(
    stats: PokerAnalytics.compute(_repo.history),
    handCount: _repo.history.length,
  );

  /// Plays [hands] hands as fast as possible, then refreshes the stats.
  Future<void> simulate(int hands) async {
    await _repo.simulate(hands);
    state = _compute();
  }

  /// Clears the recorded history (clearing does not emit, so refresh here).
  void clear() {
    _repo.clearHistory();
    state = _compute();
  }

  /// The recorded hand history as pretty-printed JSON, for export/mining.
  String exportJson() => const JsonEncoder.withIndent(
    '  ',
  ).convert(_repo.history.map((h) => h.toJson()).toList());
}

final analyticsViewModelProvider =
    NotifierProvider<AnalyticsViewModel, AnalyticsState>(
      AnalyticsViewModel.new,
    );
