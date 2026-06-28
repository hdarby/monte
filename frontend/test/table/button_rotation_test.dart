import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/features/table/data/local_game_repository.dart';

LocalGameRepository _repo() => LocalGameRepository(
  config: const TableConfig(
    allBots: true,
    playerCount: 4,
    botThinkTime: Duration.zero,
    botType: BotType.heuristic,
  ),
);

/// The set of player ids that held the button across all recorded hands.
Set<String> _buttonSeats(LocalGameRepository repo) => {
  for (final hand in repo.history)
    for (final p in hand.players)
      if (p.isButton) p.id,
};

void main() {
  group('dealer button rotation in simulation', () {
    test('rotates across seats by default', () async {
      final repo = _repo();
      addTearDown(repo.dispose);
      await repo.simulate(40);
      expect(_buttonSeats(repo).length, greaterThan(1));
    });

    test('stays pinned to one seat when fixed', () async {
      final repo = _repo();
      addTearDown(repo.dispose);
      repo.setButtonRotation(false);
      await repo.simulate(40);
      expect(_buttonSeats(repo).length, 1);
    });
  });
}
