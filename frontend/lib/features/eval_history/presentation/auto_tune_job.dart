import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:monte/features/eval_history/domain/auto_tuner.dart';
import 'package:monte/features/eval_history/presentation/eval_history_provider.dart';

/// A snapshot of what the background auto-tune job has done so far this session.
class AutoTuneJobStatus {
  const AutoTuneJobStatus({
    this.runs = 0,
    this.lastChanged = 0,
    this.lastConsumed = 0,
  });

  /// How many times the job has successfully tuned (and consumed a sample).
  final int runs;

  /// Models adjusted on the most recent successful pass.
  final int lastChanged;

  /// Hands consumed on the most recent successful pass.
  final int lastConsumed;

  AutoTuneJobStatus _bump({required int changed, required int consumed}) =>
      AutoTuneJobStatus(
        runs: runs + 1,
        lastChanged: changed,
        lastConsumed: consumed,
      );
}

/// A periodic background job that, while running, checks every ~30 minutes
/// whether enough tuning history has accumulated and — if so — *consumes* it to
/// nudge the amateur personalities' preflop parameters. It's the same offline
/// auto-tune the Analytics button runs, on a timer, with no LLM/token cost.
///
/// - Tuning takes effect on the **next** game/seat rebuild (live deciders are
///   cached), so it never disturbs the hand in progress.
/// - On a successful pass the consumed sample is **wiped**, because it was
///   produced under the *old* parameters — the tuner is a damped closed loop
///   that needs a fresh sample each step (mirrors the Analytics flow). Opponent
///   reads are intentionally left intact so live play isn't disrupted.
///
/// [build] does not start the timer; call [start] once from the app entrypoint.
/// Tests drive [runIfReady] directly, so no live timer is created under test.
class AutoTuneJob extends Notifier<AutoTuneJobStatus> {
  Timer? _timer;
  bool _running = false;

  /// How often the job wakes up to check for a consumable sample.
  static const Duration interval = Duration(minutes: 30);

  /// Enough recorded hands to bother tuning — a proxy for "at least one model
  /// has reached the per-model minimum" ([AutoTuner.defaultMinHands]).
  static const int minHands = AutoTuner.defaultMinHands;

  @override
  AutoTuneJobStatus build() {
    ref.onDispose(() => _timer?.cancel());
    return const AutoTuneJobStatus();
  }

  /// Starts the recurring timer (idempotent). Call once when the game starts.
  void start() {
    _timer ??= Timer.periodic(interval, (_) => runIfReady());
  }

  /// One tick: tune iff enough history has piled up. Returns the number of models
  /// changed (0 when it skipped or nothing qualified). Safe to call directly.
  Future<int> runIfReady() async {
    if (_running) return 0; // don't stack passes if one is still finishing
    _running = true;
    try {
      final store = ref.read(evalHistoryStoreProvider);
      final total = await store.count();
      if (total < minHands) return 0; // not enough history to bring in yet
      final hands = await store.loadAll();
      final changed =
          await ref.read(profileOverridesProvider.notifier).autoTune(hands);
      if (changed > 0) {
        // Consumed: the next window collects a fresh sample under the new params.
        await store.wipe();
        state = state._bump(changed: changed, consumed: hands.length);
      }
      return changed;
    } finally {
      _running = false;
    }
  }
}

/// The background auto-tune job. Started from the app entrypoint; not `autoDispose`
/// so it lives for the session while the game runs.
final autoTuneJobProvider =
    NotifierProvider<AutoTuneJob, AutoTuneJobStatus>(AutoTuneJob.new);
