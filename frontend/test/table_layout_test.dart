import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poker_client/data/local_game_repository.dart';
import 'package:poker_client/data/table_snapshot.dart';
import 'package:poker_client/engine/card.dart' as poker;
import 'package:poker_client/engine/game.dart';
import 'package:poker_client/ui/screens/table_screen.dart';

TableSnapshot _snapshotWith(int playerCount) {
  final seats = [
    for (var i = 0; i < playerCount; i++)
      SeatView(
        id: i == 0 ? 'human' : 'bot_$i',
        name: i == 0 ? 'You' : 'Bot $i',
        isHuman: i == 0,
        stack: 1000,
        currentBet: i == 1 ? 10 : 0,
        folded: false,
        allIn: false,
        isButton: i == 0,
        isCurrent: i == 2,
        holeCards: i == 0
            ? const [
                poker.Card(poker.Rank.ace, poker.Suit.spades),
                poker.Card(poker.Rank.king, poker.Suit.hearts),
              ]
            : null,
      ),
  ];
  return TableSnapshot(
    seats: seats,
    board: const [],
    pot: 15,
    round: BettingRound.preflop,
    currentPlayerId: 'bot_2',
    isHandOver: false,
    handInProgress: true,
    log: const ['Pre-Flop: blinds posted.'],
  );
}

Future<void> _pumpTable(WidgetTester tester, int playerCount) async {
  tester.view.physicalSize = const Size(1280, 860);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    home: TableScreen(
      snapshot: _snapshotWith(playerCount),
      repository: LocalGameRepository(),
      playerCount: playerCount,
      onOpenSettings: () {},
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('heads-up (2 players) lays out without overflow', (tester) async {
    await _pumpTable(tester, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full table (10 players) lays out without overflow', (tester) async {
    await _pumpTable(tester, 10);
    expect(tester.takeException(), isNull);
    // Every seat is rendered.
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Bot 9'), findsOneWidget);
  });
}
