import 'dart:math';

import 'package:monte/core/domain/ai/ismcts.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/ai/personality_policy.dart';
import 'package:monte/core/domain/engine/bot.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';

/// The kinds of bot brain the table can be configured with.
enum BotType {
  /// Fast, fixed heuristic. **Not player-selectable** — it ignores personality,
  /// so it's kept only as an internal baseline: the MCTS rollout self-model, the
  /// profile-postflop default, calibration's reference field, and the strength
  /// eval gate. Excluded from [selectable].
  heuristic('Heuristic'),

  /// Fast, fully personality-driven thresholds (no search).
  personality('Personality'),

  /// Strong ISMCTS search, shaped by the chosen personality.
  mcts('MCTS (Monte Carlo)');

  const BotType(this.label);

  final String label;

  /// The brains a player can actually pick for a seat. The heuristic is
  /// deliberately absent — it exists only for testing/evaluation (see above).
  static const List<BotType> selectable = [
    BotType.personality,
    BotType.mcts,
  ];

  /// A compact label for tight spots like a seat badge.
  String get shortLabel => switch (this) {
    BotType.heuristic => 'Heuristic',
    BotType.personality => 'Personality',
    BotType.mcts => 'MCTS',
  };

  /// Whether this brain is shaped by the chosen personality (the fixed
  /// heuristic ignores it).
  bool get usesPersonality => this != BotType.heuristic;
}

/// Builds the [DecisionPolicy] for the given [type], shaped by [profile].
///
/// The single place that maps configuration to a concrete bot brain, so the
/// table, evaluation runs, and future remote play all construct bots the same
/// way.
DecisionPolicy buildDecider(
  BotType type, {
  PersonalityProfile profile = const PersonalityProfile.balanced(),
  int mctsIterations = 250,
  Random? random,
}) {
  switch (type) {
    case BotType.heuristic:
      return BotStrategy(random: random);
    case BotType.personality:
      // Standalone bot: reason about ranges postflop.
      return PersonalityPolicy(profile, random: random, rangeAware: true);
    case BotType.mcts:
      return IsmctsEngine(
        config: IsmctsConfig(iterations: mctsIterations),
        profile: profile,
        random: random,
        // Rollout self-model stays cheap (category-only) — no MC-in-MC.
        rolloutPolicy: PersonalityPolicy(profile, random: random),
      );
  }
}
