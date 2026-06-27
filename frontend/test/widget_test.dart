import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('app boots and shows the table title', (tester) async {
    SharedPreferences.setMockInitialValues({});

    // The app targets desktop/web; render at a realistic window size.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: MonteApp()));
    // Settings load asynchronously, then bots take their delayed turns; let it
    // all drain so no timers are pending at teardown.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text("Texas Hold'em"), findsOneWidget);
    expect(find.textContaining('client-only'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });
}
