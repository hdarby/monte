import 'dart:math';

import 'package:monte/core/domain/ai/ismcts.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/ai/personality_policy.dart';
import 'package:monte/core/domain/engine/bot.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';

/// The kinds of bot brain the table can be configured with.
enum BotType {
  /// Fast, fixed heuristic. Snappy; good for quick evaluation runs.
  heuristic('Heuristic'),

  /// Fast, fully personality-driven thresholds (no search).
  personality('Personality'),

  /// Strong ISMCTS search, shaped by the chosen personality.
  mcts('MCTS (Monte Carlo)');

  const BotType(this.label);

  final String label;
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
      return PersonalityPolicy(profile, random: random);
    case BotType.mcts:
      return IsmctsEngine(
        config: IsmctsConfig(iterations: mctsIterations),
        profile: profile,
        random: random,
        rolloutPolicy: PersonalityPolicy(profile, random: random),
      );
  }
}
