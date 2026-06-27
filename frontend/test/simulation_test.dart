import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/table/data/local_game_repository.dart';
import 'package:monte/features/analytics/domain/analytics.dart';

void main() {
  test('all-bots simulate records the requested number of hands', () async {
    final repo = LocalGameRepository(
      config: const TableConfig(allBots: true, playerCount: 4),
    );

    await repo.simulate(50);

    expect(repo.history.length, 50);

    // Every recorded hand has the full table dealt in (stacks topped up).
    for (final hand in repo.history) {
      expect(hand.players.length, 4);
      expect(hand.actions, isNotEmpty);
    }

    // Analytics cover all four bots and stay within sane bounds.
    final stats = PokerAnalytics.compute(repo.history);
    expect(stats.length, 4);
    for (final s in stats) {
      expect(s.hands, 50);
      expect(s.vpip, inInclusiveRange(0, 100));
      expect(s.pfr, inInclusiveRange(0, 100));
      expect(
        s.pfr,
        lessThanOrEqualTo(s.vpip + 0.0001),
      ); // PFR is a subset of VPIP
    }

    repo.dispose();
  });
}
