import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poker_client/features/table/data/local_game_repository.dart';
import 'package:poker_client/features/table/presentation/table_view_model.dart';

void main() {
  test('drives an all-bots hand and mirrors the repository snapshot', () async {
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

    // Building the VM subscribes to the stream and kicks off the first hand.
    final initial = container.read(tableViewModelProvider);
    expect(initial.seats, isEmpty, reason: 'empty until the first emission');
    expect(container.read(tableViewModelProvider.notifier).isAllBots, isTrue);

    // Let the microtask newGame + zero-delay bot loop run to completion.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final snapshot = container.read(tableViewModelProvider);
    expect(snapshot.seats.length, 3);
    expect(snapshot.isHandOver, isTrue);
    expect(repo.history, isNotEmpty, reason: 'the played hand was recorded');
  });
}
