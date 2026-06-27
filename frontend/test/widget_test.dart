import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poker_client/main.dart';

void main() {
  testWidgets('app boots and shows the table title', (tester) async {
    // The app targets desktop/web; render at a realistic window size.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PokerApp());
    await tester.pump(); // first frame (newGame kicks off async)

    expect(find.text("Texas Hold'em"), findsOneWidget);
    expect(find.textContaining('client-only'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);

    // Let the bots' delayed turns drain so no timers are pending at teardown.
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });
}
