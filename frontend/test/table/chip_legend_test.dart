import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/presentation/widgets/chip_legend.dart';
import 'package:monte/core/presentation/widgets/chip_stack_view.dart';
import 'package:monte/features/tournament/domain/chip_set.dart';

/// A tournament's denominations are its private language: a colour-up silently
/// retires the small chips and introduces new ones, and nothing on the felt says
/// which is which. Hovering a stack should answer "what is the orange one worth".
void main() {
  final wsop = ChipSet.wsop().denominations;

  Future<void> pumpStack(
    WidgetTester tester, {
    int amount = 275000,
    int minDenomination = 1000,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ChipStackView(
              amount: amount,
              denominations: wsop,
              reference: amount,
              minDenomination: minDenomination,
            ),
          ),
        ),
      ),
    );
  }

  /// Moves a mouse pointer onto the stack and settles.
  Future<TestGesture> hoverStack(WidgetTester tester) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.byType(ChipStackView)));
    await tester.pumpAndSettle();
    return mouse;
  }

  group('the hover legend', () {
    testWidgets('is hidden until the stack is hovered', (tester) async {
      await pumpStack(tester);
      expect(find.byType(ChipLegend), findsNothing);
    });

    testWidgets('appears on hover and goes away again', (tester) async {
      await pumpStack(tester);
      final mouse = await hoverStack(tester);
      expect(find.byType(ChipLegend), findsOneWidget);

      await mouse.moveTo(const Offset(2000, 2000));
      await tester.pumpAndSettle();
      expect(find.byType(ChipLegend), findsNothing);
    });

    testWidgets('names every chip still in play, and its value',
        (tester) async {
      await pumpStack(tester, minDenomination: 1000);
      await hoverStack(tester);

      // Every denomination at or above the level's smallest chip.
      for (final d in wsop.where((d) => d >= 1000)) {
        expect(find.text(_chips(d)), findsOneWidget,
            reason: '$d is in play but missing from the legend');
      }
      // A chip that has been coloured up is no longer in play.
      expect(find.text(_chips(100)), findsNothing);
    });

    testWidgets('draws a swatch for each entry, not just text', (tester) async {
      await pumpStack(tester, minDenomination: 1000);
      await hoverStack(tester);
      final inPlay = wsop.where((d) => d >= 1000).length;
      expect(find.byType(ChipSwatch), findsNWidgets(inPlay));
    });

    testWidgets('shows how many of each this stack actually holds',
        (tester) async {
      // 275,000 with 1k+ chips in play is 1 x 250k + 1 x 25k.
      await pumpStack(tester, amount: 275000, minDenomination: 1000);
      await hoverStack(tester);
      expect(find.textContaining('×'), findsWidgets);
    });

    testWidgets('stays on screen even for a stack in the corner',
        (tester) async {
      // Anchoring the popup to the stack ran it off the edge for the seats
      // around the rim of the felt — which is most of them — and there is no
      // good side to flip to when a seat is in a corner. It is centred instead.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: ChipStackView(
                    amount: 275000,
                    denominations: wsop,
                    reference: 275000,
                    minDenomination: 1000,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await hoverStack(tester);

      final screen = tester.getRect(find.byType(MaterialApp));
      final legend = tester.getRect(find.byType(ChipLegend));
      expect(legend.left, greaterThanOrEqualTo(screen.left));
      expect(legend.top, greaterThanOrEqualTo(screen.top));
      expect(legend.right, lessThanOrEqualTo(screen.right));
      expect(legend.bottom, lessThanOrEqualTo(screen.bottom));
    });

    testWidgets('does not swallow clicks meant for the felt', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => tapped = true,
                  ),
                ),
                Center(
                  child: ChipStackView(
                    amount: 275000,
                    denominations: wsop,
                    reference: 275000,
                    minDenomination: 1000,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await hoverStack(tester);
      expect(find.byType(ChipLegend), findsOneWidget);
      // A click through the middle of the visible legend must reach the felt.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('can be switched off', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ChipStackView(
                amount: 275000,
                denominations: wsop,
                reference: 275000,
                minDenomination: 1000,
                showLegendOnHover: false,
              ),
            ),
          ),
        ),
      );
      await hoverStack(tester);
      expect(find.byType(ChipLegend), findsNothing);
    });
  });

  group('the legend on its own', () {
    testWidgets('orders chips biggest first, like a real rack', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChipLegend(denominations: wsop, minDenomination: 5000),
          ),
        ),
      );
      final shown = tester
          .widgetList<ChipSwatch>(find.byType(ChipSwatch))
          .map((s) => s.denomination)
          .toList();
      expect(shown, isNotEmpty);
      expect(shown, orderedEquals([...shown]..sort((a, b) => b.compareTo(a))));
      expect(shown.every((d) => d >= 5000), isTrue);
    });

    testWidgets('omits the holdings column when no amount is given',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChipLegend(denominations: wsop, minDenomination: 5000),
          ),
        ),
      );
      expect(find.textContaining('×'), findsNothing);
    });
  });
}

/// Mirrors `formatChips` for the values the legend prints.
String _chips(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
