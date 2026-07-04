import 'dart:math';

import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';
import 'package:monte/features/eval_history/domain/eval_metrics.dart';
import 'package:monte/features/eval_history/domain/profile_overrides.dart';

/// Offline, no-LLM closed-loop tuner. Reads a recorded tuning sample and nudges
/// each amateur personality's *effective* preflop baseline so its measured
/// VPIP / PFR / 3-bet move toward the type's intended targets. One damped step
/// per call — repeat *simulate → tune → simulate* to converge (same idea as
/// `ProfileCalibrator`, but persisted as [ProfileOverrides]).
///
/// Pros self-calibrate and custom `brain:style` bots have no canonical target, so
/// only profiles in [homeGameProfiles] are tuned; the rest are left as-is.
class AutoTuner {
  const AutoTuner();

  /// A model needs at least this many recorded hands before it's tuned, so a
  /// tiny sample can't swing its parameters wildly.
  static const int defaultMinHands = 300;

  static ProfileOverrides tune(
    ProfileOverrides current,
    List<EvalHand> hands, {
    int minHands = defaultMinHands,
  }) {
    final metrics = EvalMetrics.byModel(hands);
    final amateurs = {for (final p in homeGameProfiles) p.id: p};
    final next = Map<String, StrategicBaseline>.from(current.byModel);

    metrics.forEach((modelId, m) {
      final profile = amateurs[modelId];
      if (profile == null || m.hands < minHands) return;

      final intended = profile.strategicBaseline;
      // The input that produced this sample (defaults to the type's target).
      final effNow = current.byModel[modelId] ?? intended;

      var vpip = _step(effNow.vpipTarget, intended.vpipTarget, m.vpip / 100);
      var pfr = _step(effNow.pfrTarget, intended.pfrTarget, m.pfr / 100);
      var threeBet =
          _step(effNow.threeBetFrequency, intended.threeBetFrequency, m.threeBet / 100);

      // Keep the bands nested: 3-bet ⊆ open ⊆ VPIP.
      pfr = min(pfr, vpip);
      threeBet = min(threeBet, pfr);

      next[modelId] = StrategicBaseline(
        vpipTarget: vpip,
        pfrTarget: pfr,
        threeBetFrequency: threeBet,
        gtoAdherenceWeight: intended.gtoAdherenceWeight, // not tuned
      );
    });

    return ProfileOverrides(next);
  }

  /// One damped proportional step of the admitted input [q] toward [target],
  /// given the [measured] frequency it produced. Ratio clamped to avoid
  /// overshoot; result kept in a sane fraction range.
  static double _step(double q, double target, double measured) {
    if (target <= 0) return 0.0;
    final ratio = measured <= 1e-6 ? 2.0 : (target / measured).clamp(0.5, 2.0);
    return (q * pow(ratio, 0.7)).clamp(0.01, 0.95);
  }
}
