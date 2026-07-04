import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:monte/core/di/game_providers.dart';
import 'package:monte/features/analytics/domain/analytics.dart';
import 'package:monte/features/eval_history/domain/eval_metrics.dart';
import 'package:monte/features/eval_history/presentation/eval_history_provider.dart';
import 'package:monte/features/table/domain/game_repository.dart';

/// Immutable analytics view state.
class AnalyticsState {
  const AnalyticsState({
    required this.stats,
    required this.handCount,
    this.behaviorById = const {},
    this.rotateButton = true,
    this.isSimulating = false,
    this.simulated = 0,
    this.target = 0,
    this.tuningCount = 0,
    this.tuningMetrics = const [],
    this.tuningLoading = false,
  });

  final List<PlayerStats> stats;
  final int handCount;

  /// Permanent tuning history: total hands recorded, and per-model metrics
  /// (loaded on demand from the on-disk full-information record).
  final int tuningCount;
  final List<ModelMetrics> tuningMetrics;
  final bool tuningLoading;

  /// Whether the dealer button rotates each hand during simulation.
  final bool rotateButton;

  /// Player id -> behavior model label (brain + style), for showing which
  /// personality each row represents.
  final Map<String, String> behaviorById;

  /// Progress of an in-flight simulation run.
  final bool isSimulating;
  final int simulated;
  final int target;

  double get progress => target == 0 ? 0 : (simulated / target).clamp(0.0, 1.0);

  AnalyticsState copyWith({
    List<PlayerStats>? stats,
    int? handCount,
    Map<String, String>? behaviorById,
    bool? rotateButton,
    bool? isSimulating,
    int? simulated,
    int? target,
    int? tuningCount,
    List<ModelMetrics>? tuningMetrics,
    bool? tuningLoading,
  }) => AnalyticsState(
    stats: stats ?? this.stats,
    handCount: handCount ?? this.handCount,
    behaviorById: behaviorById ?? this.behaviorById,
    rotateButton: rotateButton ?? this.rotateButton,
    isSimulating: isSimulating ?? this.isSimulating,
    simulated: simulated ?? this.simulated,
    target: target ?? this.target,
    tuningCount: tuningCount ?? this.tuningCount,
    tuningMetrics: tuningMetrics ?? this.tuningMetrics,
    tuningLoading: tuningLoading ?? this.tuningLoading,
  );
}

/// Computes [PlayerStats] from the game repository's recorded hand histories,
/// recomputing whenever the table emits (a hand played, a simulation finished).
class AnalyticsViewModel extends Notifier<AnalyticsState> {
  GameRepository get _repo => ref.read(gameRepositoryProvider);

  /// While a batch is running we drive progress ourselves and skip the per-emit
  /// recompute (recomputing over a growing history every chunk is O(n²)).
  bool _suppressRecompute = false;
  bool _cancelRequested = false;

  /// Hands per chunk: small enough to keep the UI responsive and Stop snappy,
  /// large enough that per-chunk overhead stays negligible.
  static const _chunk = 200;

  @override
  AnalyticsState build() {
    final repo = ref.watch(gameRepositoryProvider);
    final sub = repo.watch().listen((_) {
      if (!_suppressRecompute) state = _compute();
    });
    ref.onDispose(sub.cancel);
    return _compute();
  }

  AnalyticsState _compute() {
    final behavior = <String, String>{};
    for (final seat in _repo.snapshot.seats) {
      if (seat.behavior != null) behavior[seat.id] = seat.behavior!;
    }
    return AnalyticsState(
      stats: PokerAnalytics.compute(_repo.history),
      handCount: _repo.history.length,
      behaviorById: behavior,
      rotateButton: _repo.buttonRotates,
    );
  }

  /// Pins the dealer button to one seat (false) or lets it rotate (true) for
  /// subsequent simulation. Recreates the table, keeping recorded history.
  void setButtonRotation(bool rotate) {
    if (state.isSimulating) return;
    _repo.setButtonRotation(rotate);
    state = _compute();
  }

  /// Plays [hands] hands in chunks so the UI stays responsive and shows
  /// progress, then refreshes the stats. Safe to Stop mid-run.
  Future<void> simulate(int hands) async {
    if (hands <= 0 || state.isSimulating) return;
    _cancelRequested = false;
    _suppressRecompute = true;
    state = state.copyWith(isSimulating: true, simulated: 0, target: hands);
    try {
      var done = 0;
      while (done < hands && !_cancelRequested) {
        final n = (hands - done) < _chunk ? hands - done : _chunk;
        await _repo.simulate(n);
        done += n;
        state = state.copyWith(simulated: done);
        // Yield so the progress bar repaints and Stop can be observed.
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      _suppressRecompute = false;
      // Persist the tuning records this run produced, then refresh the count.
      final store = ref.read(evalHistoryStoreProvider);
      await store.flush();
      state = _compute().copyWith(tuningCount: await store.count());
    }
  }

  /// Loads the persisted tuning history and computes per-model metrics for
  /// display. Kept on-demand — the file can be large.
  Future<void> loadTuning() async {
    state = state.copyWith(tuningLoading: true);
    final store = ref.read(evalHistoryStoreProvider);
    final hands = await store.loadAll();
    final metrics = EvalMetrics.byModel(hands).values.toList()
      ..sort((a, b) => b.bbPer100.compareTo(a.bbPer100));
    state = state.copyWith(
      tuningLoading: false,
      tuningCount: hands.length,
      tuningMetrics: metrics,
    );
  }

  /// Wipes ALL tuning memory: the on-disk full-information history *and* the
  /// in-session recorded hands + opponent reads — the reset to run clean after
  /// changing a model, so stale behavior can't pollute tuning.
  Future<void> wipeTuning() async {
    await ref.read(evalHistoryStoreProvider).wipe();
    _repo.resetMemory();
    state = _compute().copyWith(
      tuningCount: 0,
      tuningMetrics: const [],
      tuningLoading: false,
    );
  }

  /// Offline auto-tune: reads the tuning file and nudges amateur personalities'
  /// preflop parameters toward their type targets (no tokens), then resets the
  /// now-stale sample. Returns how many models were adjusted this pass.
  Future<int> autoTunePersonalities() async {
    final hands = await ref.read(evalHistoryStoreProvider).loadAll();
    final changed = await ref
        .read(profileOverridesProvider.notifier)
        .autoTune(hands);
    await wipeTuning(); // sample is stale under the new params
    return changed;
  }

  /// Reverts every personality to its code-defined type (clears tuning overrides).
  Future<void> resetTuningAdjustments() =>
      ref.read(profileOverridesProvider.notifier).reset();

  /// The full-information tuning history as pretty JSON (one array), for export.
  Future<String> tuningExportJson() async {
    final hands = await ref.read(evalHistoryStoreProvider).loadAll();
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(hands.map((h) => h.toJson()).toList());
  }

  /// Requests the current simulation stop at the next chunk boundary.
  void stopSimulation() => _cancelRequested = true;

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
