import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/ai/ismcts.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/ai/personality_policy.dart';
import 'package:monte/core/domain/engine/bot.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';
import 'package:monte/features/table/data/local_game_repository.dart';

PokerGame _freshHand(int seed) => PokerGame(
  players: [
    Player(id: 'p0', name: 'P0', stack: 1000),
    Player(id: 'p1', name: 'P1', stack: 1000),
  ],
  deck: Deck(random: Random(seed)),
)..startHand();

void main() {
  group('buildDecider', () {
    test('maps each bot type to the right brain, all DecisionPolicies', () {
      expect(buildDecider(BotType.heuristic), isA<BotStrategy>());
      expect(buildDecider(BotType.personality), isA<PersonalityPolicy>());
      expect(buildDecider(BotType.mcts), isA<IsmctsEngine>());
      for (final t in BotType.values) {
        expect(buildDecider(t), isA<DecisionPolicy>());
      }
    });

    test('selectable brains exclude the test-only heuristic', () {
      // The heuristic stays buildable (rollout/postflop/eval baseline) but must
      // never be offered to the player.
      expect(BotType.selectable, isNot(contains(BotType.heuristic)));
      expect(BotType.selectable, contains(BotType.personality));
      expect(BotType.selectable, contains(BotType.mcts));
      expect(buildDecider(BotType.heuristic), isA<BotStrategy>());
    });

    test('every brain returns a legal action for the player to act', () {
      for (final type in BotType.values) {
        final game = _freshHand(11);
        final decider = buildDecider(
          type,
          profile: const PersonalityProfile.lag(),
          mctsIterations: 40,
          random: Random(1),
        );
        final action = decider.decide(game, game.currentPlayer!);
        expect(
          () => game.clone().applyAction(action),
          returnsNormally,
          reason: '${type.name} produced an illegal action',
        );
      }
    });
  });

  group('LocalGameRepository with configured bots', () {
    test('all-bots MCTS evaluation records every hand', () async {
      final repo = LocalGameRepository(
        config: const TableConfig(
          playerCount: 3,
          allBots: true,
          botType: BotType.mcts,
          personality: PersonalityProfile.tag(),
          mctsIterations: 30,
        ),
      );
      addTearDown(repo.dispose);

      await repo.simulate(3);

      expect(repo.history, hasLength(3));
      expect(repo.isAllBots, isTrue);
    });

    test('all-bots personality evaluation records every hand', () async {
      final repo = LocalGameRepository(
        config: const TableConfig(
          playerCount: 4,
          allBots: true,
          botType: BotType.personality,
          personality: PersonalityProfile.maniac(),
        ),
      );
      addTearDown(repo.dispose);

      await repo.simulate(5);

      expect(repo.history, hasLength(5));
    });
  });
}
