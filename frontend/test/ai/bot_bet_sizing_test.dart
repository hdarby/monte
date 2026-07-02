import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/features/table/data/local_game_repository.dart';

// At 25/50 with a stake that's a multiple of the small blind, every bot bet/raise
// should snap to a human-style round number (a multiple of the 25 small blind),
// never an arbitrary value like 37 or 43.
void main() {
  test('bot bet/raise amounts snap to the stake denomination', () async {
    const sb = 25, bb = 50;
    final repo = LocalGameRepository(
      config: const TableConfig(
        allBots: true,
        playerCount: 4,
        startingStack: 5000,
        smallBlind: sb,
        bigBlind: bb,
        botType: BotType.personality,
        botThinkTime: Duration.zero,
        seatBots: [
          BotSpec(brain: BotType.personality, style: PersonalityArchetype.tag),
          BotSpec(brain: BotType.personality, style: PersonalityArchetype.lag),
          BotSpec(brain: BotType.heuristic),
          BotSpec(brain: BotType.personality, style: PersonalityArchetype.maniac),
        ],
      ),
    );
    addTearDown(repo.dispose);

    await repo.simulate(400);

    var checked = 0;
    for (final hand in repo.history) {
      for (final a in hand.actions) {
        if (a.type == ActionType.bet || a.type == ActionType.raise) {
          expect(
            a.amount % sb,
            0,
            reason: 'a ${a.type.name} of ${a.amount} is not a multiple of $sb',
          );
          checked++;
        }
      }
    }
    expect(checked, greaterThan(50), reason: 'expected plenty of bets to check');
  });
}
