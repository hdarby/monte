import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('app boots and shows the table title', (tester) async {
    // Instant pace = no bot think-timers, so pumpAndSettle drains cleanly.
    SharedPreferences.setMockInitialValues({'play_pace': 'instant'});

    // The app targets desktop/web; render at a realistic window size.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: MonteApp()));
    // Settings load asynchronously, then bots take their turns; let it drain.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Each session boots onto the Settings screen; dismiss it to reach the table.
    await _dismissStartupSettings(tester);

    expect(find.text("Texas Hold'em"), findsOneWidget);
    expect(find.textContaining('client-only'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });

  testWidgets('app boots cleanly with non-default stored settings', (
    tester,
  ) async {
    // Stored settings that differ from the defaults — this is what exposed a
    // first-frame "setState during build" from the settings -> repository
    // provider cascade (empty prefs masked it).
    SharedPreferences.setMockInitialValues({
      'player_count': 6,
      'show_big_blinds': true,
      'all_bots': false,
      'bot_type': 'mcts',
      'bot_personality': 'lag',
      'play_pace': 'instant',
    });

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: MonteApp()));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await _dismissStartupSettings(tester);

    expect(tester.takeException(), isNull);
    expect(find.text("Texas Hold'em"), findsOneWidget);
  });
}

/// Each session boots onto the Settings screen (see `_maybePromptStartup`).
/// Tap its "Cancel" (an [OutlinedButton]) to drop onto the table.
Future<void> _dismissStartupSettings(WidgetTester tester) async {
  final cancel = find.widgetWithText(OutlinedButton, 'Cancel');
  expect(cancel, findsOneWidget, reason: 'boot should open the Settings screen');
  await tester.tap(cancel);
  await tester.pumpAndSettle(const Duration(seconds: 1));
}
