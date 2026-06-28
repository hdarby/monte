import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end check that the "Show behavior model on seats" setting actually
/// drives the seat badges: toggling it in Settings must make the badge appear
/// on the table without restarting the game.
void main() {
  testWidgets('toggling the behavior setting shows seat badges', (tester) async {
    // Heads-up vs a personality bot, behavior badges off to start.
    SharedPreferences.setMockInitialValues({
      'player_count': 2,
      'bot_type': 'personality',
      'show_behavior': false,
    });

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: MonteApp()));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // The game starts on the personality chooser; keep the default lineup.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Off by default: no badge on the table.
    expect(find.textContaining('· Personality'), findsNothing);

    // Open Settings and flip the toggle on.
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    final toggle = find.widgetWithText(
      SwitchListTile,
      'Show behavior model on seats',
    );
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    final apply = find.widgetWithText(FilledButton, 'Apply');
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Back on the table, the bot's behavior badge is now visible.
    expect(find.textContaining('· Personality'), findsWidgets);
  });
}
