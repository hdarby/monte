import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poker_client/features/analytics/presentation/analytics_view_model.dart';
import 'package:poker_client/features/table/data/local_game_repository.dart';
import 'package:poker_client/features/table/presentation/table_view_model.dart';

void main() {
  test('computes stats after simulate, exports JSON, and clears', () async {
    final repo = LocalGameRepository(
      config: const TableConfig(
        allBots: true,
        playerCount: 3,
        botThinkTime: Duration.zero,
      ),
    );
    final container = ProviderContainer(
      overrides: [gameRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    addTearDown(repo.dispose);

    final vm = container.read(analyticsViewModelProvider.notifier);
    expect(container.read(analyticsViewModelProvider).handCount, 0);

    await vm.simulate(20);
    final state = container.read(analyticsViewModelProvider);
    expect(state.handCount, 20);
    expect(state.stats.length, 3);

    final json = vm.exportJson();
    expect(json, contains('handNumber'));
    expect(json, contains('actions'));

    vm.clear();
    expect(container.read(analyticsViewModelProvider).handCount, 0);
    expect(container.read(analyticsViewModelProvider).stats, isEmpty);
  });
}
