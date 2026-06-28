import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/opponent_model.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/ai/personality_policy.dart';
import 'package:monte/core/domain/engine/bot.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/features/table/data/local_game_repository.dart';

void main() {
  group('OpponentModel', () {
    test('reads distinguish a nit from a maniac and firm up with sample', () {
      // Seat 0 = nit (very tight), seat 1 = maniac (very loose); rest heuristic.
      DecisionPolicy decider(int i) => switch (i) {
        0 => PersonalityPolicy(
          PersonalityArchetype.nit.profile,
          random: Random(1),
        ),
        1 => PersonalityPolicy(
          PersonalityArchetype.maniac.profile,
          random: Random(2),
        ),
        _ => BotStrategy(random: Random(10 + i)),
      };

      final repo = LocalGameRepository(
        config: TableConfig(
          allBots: true,
          playerCount: 4,
          botThinkTime: Duration.zero,
          deciderBuilder: decider,
        ),
      );
      addTearDown(repo.dispose);
      repo.simulate(800);

      final model = OpponentModel();
      for (final hand in repo.history) {
        model.observe(hand);
      }

      final nit = model.of('bot_0');
      final maniac = model.of('bot_1');

      // The maniac plays far more hands than the nit — a clear, usable read.
      expect(maniac.vpip, greaterThan(nit.vpip + 0.2));
      expect(maniac.pfr, greaterThan(nit.pfr));
      // Plenty of hands seen, so confidence is high and shrinkage is small.
      expect(nit.confidence, greaterThan(0.95));
      expect(maniac.confidence, greaterThan(0.95));
    });

    test('an unseen player reports the neutral prior at zero confidence', () {
      final o = OpponentModel().of('nobody');
      expect(o.hands, 0);
      expect(o.confidence, 0);
      expect(o.vpip, closeTo(0.24, 0.001)); // population prior
      expect(o.aggressionFactor, 1.0); // neutral default
    });
  });
}
