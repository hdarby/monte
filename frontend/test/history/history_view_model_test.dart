import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/di/game_providers.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/features/history/presentation/history_view_model.dart';
import 'package:monte/features/table/data/local_game_repository.dart';

import '../_helpers.dart';

List<Card> _deal() {
  final placed = <int, Card>{
    0: card('As'), 2: card('Ah'), // human
    1: card('7c'), 3: card('2d'), // bot
    5: card('Kd'), 6: card('Qs'), 7: card('9h'), 9: card('4c'), 11: card('3s'),
  };
  final used = placed.values.toSet();
  final rest = [
    for (final suit in Suit.values)
      for (final rank in Rank.values)
        if (!used.contains(Card(rank, suit))) Card(rank, suit),
  ];
  var r = 0;
  return [for (var i = 0; i < 52; i++) placed[i] ?? rest[r++]];
}

void main() {
  test('exposes recorded hands newest-first, reflecting the repository', () async {
    final repo = LocalGameRepository(
      config: TableConfig(
        playerCount: 2,
        botType: BotType.heuristic,
        botThinkTime: Duration.zero,
        deckBuilder: () => Deck.stacked(_deal()),
      ),
    );
    addTearDown(repo.dispose);

    final container = ProviderContainer(
      overrides: [gameRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    // Empty before any hand.
    expect(container.read(historyViewModelProvider).isEmpty, isTrue);

    await repo.newGame();
    await repo.submitAction(const GameAction.allIn()); // hand 1 resolves
    await repo.startNextHand();
    await repo.submitAction(const GameAction.allIn()); // hand 2 resolves

    final state = container.read(historyViewModelProvider);
    expect(state.hands, hasLength(repo.history.length));
    expect(state.hands.length, greaterThanOrEqualTo(2));
    // Newest first: the view's first hand is the repository's last.
    expect(state.hands.first.handNumber, repo.history.last.handNumber);
    expect(state.hands.first.handNumber,
        greaterThan(state.hands.last.handNumber));
  });
}
