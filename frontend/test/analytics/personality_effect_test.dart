import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/features/analytics/domain/analytics.dart';
import 'package:monte/features/table/data/local_game_repository.dart';

PlayerStats _byId(List<PlayerStats> stats, String id) =>
    stats.firstWhere((s) => s.id == id);

void main() {
  test('personalities visibly change how bots play (VPIP)', () async {
    final repo = LocalGameRepository(
      config: const TableConfig(
        allBots: true,
        playerCount: 3,
        botType: BotType.personality,
        botThinkTime: Duration.zero,
        seatBots: [
          BotSpec(brain: BotType.personality, style: PersonalityArchetype.nit),
          BotSpec(
            brain: BotType.personality,
            style: PersonalityArchetype.maniac,
          ),
          BotSpec(
            brain: BotType.personality,
            style: PersonalityArchetype.balanced,
          ),
        ],
      ),
    );
    addTearDown(repo.dispose);

    await repo.simulate(600);
    final stats = PokerAnalytics.compute(repo.history);

    final nit = _byId(stats, 'bot_0');
    final maniac = _byId(stats, 'bot_1');

    // A maniac plays far more hands than a nit — concrete proof the personality
    // axes actually drive behaviour.
    expect(maniac.vpip, greaterThan(nit.vpip));
    expect(maniac.vpip - nit.vpip, greaterThan(15));
  });

  test('a simulation run tops up stacks and never stops early', () async {
    // Not all-bots: previously stacks depleted and the run halted at the first
    // bust. Evaluation now tops up every hand, so all requested hands play.
    final repo = LocalGameRepository(
      config: const TableConfig(
        playerCount: 3,
        startingStack: 200,
        botType: BotType.personality,
        botThinkTime: Duration.zero,
      ),
    );
    addTearDown(repo.dispose);

    await repo.simulate(300);
    expect(repo.history.length, 300);
  });
}
