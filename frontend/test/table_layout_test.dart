import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/card.dart' as poker;
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/features/table/domain/table_snapshot.dart';
import 'package:monte/features/table/presentation/table_screen.dart';

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
        // A deliberately long label to stress the seat's fixed footprint.
        behavior: i == 0 ? null : 'Station · Personality',
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

Future<void> _pumpTable(
  WidgetTester tester,
  int playerCount, {
  bool showBehavior = false,
}) async {
  tester.view.physicalSize = const Size(1280, 860);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: TableScreen(
        snapshot: _snapshotWith(playerCount),
        isAllBots: false,
        playerCount: playerCount,
        showBehavior: showBehavior,
        onAction: (_) {},
        onNewGame: () {},
        onNextHand: () {},
        onOpenSettings: () {},
        onOpenAnalytics: () {},
        onOpenHistory: () {},
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('heads-up (2 players) lays out without overflow', (tester) async {
    await _pumpTable(tester, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full table (10 players) lays out without overflow', (
    tester,
  ) async {
    await _pumpTable(tester, 10);
    expect(tester.takeException(), isNull);
    // Every seat is rendered.
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Bot 9'), findsOneWidget);
  });

  testWidgets('full table with behavior badges lays out without overflow', (
    tester,
  ) async {
    await _pumpTable(tester, 10, showBehavior: true);
    expect(tester.takeException(), isNull);
    // Badges are present but bounded — the long label is ellipsised, not
    // overflowing, and the seat keeps its fixed footprint.
    expect(find.textContaining('Station'), findsWidgets);
  });

  testWidgets('long names and large amounts fit without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final seats = [
      SeatView(
        id: 'human',
        name: 'Jonathan Q. Longsurname',
        isHuman: true,
        stack: 1234567,
        currentBet: 0,
        folded: false,
        allIn: false,
        isButton: true,
        isCurrent: false,
      ),
      SeatView(
        id: 'bot_1',
        name: 'Maximilian Bettington',
        isHuman: false,
        stack: 999999,
        currentBet: 123456, // huge amount that would blow past the small tag
        raiseLevel: 3,
        folded: false,
        allIn: false,
        isButton: false,
        isCurrent: true,
      ),
      SeatView(
        id: 'bot_2',
        name: 'Alexandra Winnington',
        isHuman: false,
        stack: 250000,
        currentBet: 0,
        wonAmount: 987654,
        wonNet: 987654,
        folded: false,
        allIn: false,
        isButton: false,
        isCurrent: false,
      ),
    ];
    final snapshot = TableSnapshot(
      seats: seats,
      board: const [],
      pot: 500000,
      round: BettingRound.flop,
      currentPlayerId: 'bot_1',
      isHandOver: false,
      handInProgress: true,
      log: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TableScreen(
          snapshot: snapshot,
          isAllBots: false,
          playerCount: 3,
          onAction: (_) {},
          onNewGame: () {},
          onNextHand: () {},
          onOpenSettings: () {},
          onOpenAnalytics: () {},
          onOpenHistory: () {},
        ),
      ),
    );
    await tester.pump();

    // Nothing overflows despite the long names and large amounts.
    expect(tester.takeException(), isNull);
    // The bet/won amounts are shown in full (scaled, never truncated).
    expect(find.text('BET \$123456'), findsOneWidget);
    expect(find.text('WON +\$987654'), findsOneWidget);
    // The human's long name collapses to an initial + surname rather than
    // ellipsising.
    expect(find.text('J. Longsurname'), findsOneWidget);
  });

  testWidgets('winner banner announces who won once the hand is over', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final seats = [
      SeatView(
        id: 'human',
        name: 'You',
        isHuman: true,
        stack: 1000,
        currentBet: 0,
        folded: false,
        allIn: false,
        isButton: true,
        isCurrent: false,
      ),
      SeatView(
        id: 'bot_1',
        name: 'Ivey',
        isHuman: false,
        stack: 1120,
        currentBet: 0,
        // Collected a 120 pot, but 50 of it was their own money going in, so
        // the hand made them 70. The banner must report the 70.
        wonAmount: 120,
        wonNet: 70,
        folded: false,
        allIn: false,
        isButton: false,
        isCurrent: false,
      ),
    ];
    final snapshot = TableSnapshot(
      seats: seats,
      board: const [],
      pot: 0,
      round: BettingRound.river,
      currentPlayerId: null,
      isHandOver: true,
      handInProgress: false,
      log: const ['Ivey wins the pot.'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TableScreen(
          snapshot: snapshot,
          isAllBots: false,
          playerCount: 2,
          onAction: (_) {},
          onNewGame: () {},
          onNextHand: () {},
          onOpenSettings: () {},
          onOpenAnalytics: () {},
          onOpenHistory: () {},
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Ivey wins — +\$70'), findsOneWidget);
    expect(find.text('Ivey wins \$120'), findsNothing,
        reason: 'the pot collected is mostly the winner\'s own money back');
  });
}
