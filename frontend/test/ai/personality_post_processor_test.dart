import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/action_candidate.dart';
import 'package:monte/core/domain/ai/personality_post_processor.dart';
import 'package:monte/core/domain/engine/actions.dart';

/// Unit coverage for [PersonalityPostProcessor.mix] in isolation from the full
/// postflop evaluator: does the bounded logistic actually mix near-equal
/// candidates at roughly the score-implied ratio, and leave a genuine
/// blowout alone?
void main() {
  group('PersonalityPostProcessor.mix', () {
    const chosenAction = GameAction.call();
    const runnerUpAction = GameAction.fold();

    /// Runs [trials] independent seeds (one [PersonalityPostProcessor] per
    /// seed, matching how the policy constructs it) and returns the fraction
    /// that picked [chosen].
    double chosenRate(
      ActionCandidate chosen,
      ActionCandidate runnerUp, {
      int trials = 4000,
    }) {
      var picks = 0;
      for (var seed = 0; seed < trials; seed++) {
        final pp = PersonalityPostProcessor(Random(seed));
        if (identical(pp.mix(chosen, runnerUp).action, chosen.action)) {
          picks++;
        }
      }
      return picks / trials;
    }

    test('a dead-even gap (margin 0) is picked ~50/50 across seeds', () {
      final chosen = ActionCandidate(chosenAction, label: 'call', margin: 0.0);
      final runnerUp =
          ActionCandidate(runnerUpAction, label: 'fold', margin: 0.0);
      final rate = chosenRate(chosen, runnerUp);
      expect(rate, closeTo(0.5, 0.05),
          reason: 'gap == 0 must be a genuine coin-flip, not a hard lean');
    });

    test('a gap inside the window is mixed at the logistic-implied ratio',
        () {
      // Half of closeDecisionMargin (0.01) → k=40 gives pChosen =
      // 1 / (1 + exp(-40 * 0.005)) ≈ 0.5498 — the exact formula `mix` uses.
      const gap = PersonalityPostProcessor.closeDecisionMargin / 2;
      const k = 40.0;
      final expected = 1.0 / (1.0 + exp(-k * gap));

      final chosen = ActionCandidate(chosenAction, label: 'call', margin: gap);
      final runnerUp =
          ActionCandidate(runnerUpAction, label: 'fold', margin: 0.0);
      final rate = chosenRate(chosen, runnerUp);
      expect(rate, closeTo(expected, 0.05),
          reason:
              'a genuine near-tie should land at its logistic-implied ratio, '
              'not 50/50 and not a hard cutoff');
    });

    test('a wide gap outside the window is chosen deterministically', () {
      // Comfortably outside closeDecisionMargin (0.01).
      final chosen =
          ActionCandidate(chosenAction, label: 'call', margin: 0.20);
      final runnerUp =
          ActionCandidate(runnerUpAction, label: 'fold', margin: 0.0);
      for (var seed = 0; seed < 200; seed++) {
        final pp = PersonalityPostProcessor(Random(seed));
        expect(pp.mix(chosen, runnerUp).action, chosenAction,
            reason: 'a hand nowhere near its bar must never flip on a coin');
      }
    });

    test('a null runnerUp is always a no-op', () {
      final chosen = ActionCandidate(chosenAction, label: 'call', margin: 0.0);
      for (var seed = 0; seed < 50; seed++) {
        final pp = PersonalityPostProcessor(Random(seed));
        expect(pp.mix(chosen, null), same(chosen));
      }
    });
  });
}
