import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/table/domain/table_snapshot.dart';
import 'package:monte/features/table/presentation/widgets/player_seat.dart';
import 'package:monte/features/table/presentation/widgets/playing_card_widget.dart';

import '../_helpers.dart';

Future<void> _pumpSeat(WidgetTester tester, SeatView seat) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: PlayerSeat(seat: seat)))),
    );

Iterable<PlayingCardWidget> _faceUp(WidgetTester tester) => tester
    .widgetList<PlayingCardWidget>(find.byType(PlayingCardWidget))
    .where((w) => !w.faceDown && w.card != null);

void main() {
  testWidgets('a winning bot\'s revealed cards stay visible at showdown', (tester) async {
    // Bot that won the pot with its hand shown (holeCards populated at reveal).
    await _pumpSeat(
      tester,
      SeatView(
        id: 'b', name: 'Bot', isHuman: false, stack: 900, currentBet: 0,
        folded: false, allIn: false, isButton: false, isCurrent: false,
        wonAmount: 250, holeCards: cards('As Kd'),
      ),
    );
    await tester.pump();

    // Both revealed hole cards render face-up — not buried under an opaque banner.
    expect(_faceUp(tester).length, 2,
        reason: 'the revealed hand must stay visible under the money strip');
    // ...and the won amount is still shown (as the translucent strip).
    expect(find.textContaining('WON'), findsOneWidget);
  });

  testWidgets('a betting bot with face-down cards still shows the full banner', (tester) async {
    // Mid-hand: cards are face down (no info), so the bet fully overwrites them.
    await _pumpSeat(
      tester,
      const SeatView(
        id: 'b', name: 'Bot', isHuman: false, stack: 900, currentBet: 50,
        folded: false, allIn: false, isButton: false, isCurrent: false,
        raiseLevel: 1,
      ),
    );
    await tester.pump();

    expect(_faceUp(tester), isEmpty, reason: 'face-down cards carry no info');
    expect(find.textContaining('BET'), findsOneWidget);
  });
}
