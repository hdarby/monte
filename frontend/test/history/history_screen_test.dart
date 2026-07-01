import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/di/game_providers.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/features/history/presentation/history_screen.dart';
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
  testWidgets('renders the street-grouped action log for a played hand',
      (tester) async {
    final repo = LocalGameRepository(
      config: TableConfig(
        playerCount: 2,
        botType: BotType.heuristic,
        botThinkTime: Duration.zero,
        deckBuilder: () => Deck.stacked(_deal()),
      ),
    );
    addTearDown(repo.dispose);
    // Drive the repo with real async (it awaits bot-think timers that a
    // fake-async testWidgets zone won't advance on its own).
    await tester.runAsync(() async {
      await repo.newGame();
      await repo.submitAction(const GameAction.allIn()); // human shoves, bot folds
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [gameRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );
    await tester.pump();

    // Street header and both actions from the sequence are shown.
    expect(find.textContaining('PRE-FLOP'), findsOneWidget);
    expect(find.textContaining('all-in'), findsOneWidget);
    expect(find.textContaining('folds'), findsOneWidget);
    // A pot annotation appears on action lines.
    expect(find.textContaining('pot '), findsWidgets);
  });
}
