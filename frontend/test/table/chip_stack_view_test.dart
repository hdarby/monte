import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/presentation/widgets/chip_stack_view.dart';
import 'package:monte/features/tournament/domain/chip_set.dart';

/// The whole point of the graphic is that a glance at the felt tells you who is
/// deep and who is short, so the invariant under test is: more chips renders as
/// visibly more chips.
void main() {
  final wsop = ChipSet.wsop().denominations;

  Future<int> chipsDrawn(
    WidgetTester tester, {
    required int amount,
    required int reference,
    int minDenomination = 100,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ChipStackView(
              amount: amount,
              denominations: wsop,
              reference: reference,
              minDenomination: minDenomination,
            ),
          ),
        ),
      ),
    );
    // Every drawn chip is a Container inside the view; count the leaves.
    return find
        .descendant(
          of: find.byType(ChipStackView),
          matching: find.byType(Container),
        )
        .evaluate()
        .length;
  }

  testWidgets('the chip leader draws more chips than a short stack',
      (tester) async {
    const ref = 500000;
    final leader = await chipsDrawn(tester, amount: 500000, reference: ref);
    final middling = await chipsDrawn(tester, amount: 150000, reference: ref);
    final short = await chipsDrawn(tester, amount: 10000, reference: ref);

    expect(leader, greaterThan(middling));
    expect(middling, greaterThan(short));
    expect(short, greaterThanOrEqualTo(1));
  });

  testWidgets('height is monotonic in stack size', (tester) async {
    const ref = 200000;
    var previous = 0;
    for (final amount in [5000, 25000, 60000, 120000, 200000]) {
      final drawn = await chipsDrawn(tester, amount: amount, reference: ref);
      expect(
        drawn,
        greaterThanOrEqualTo(previous),
        reason: '$amount drew fewer chips than the stack below it',
      );
      previous = drawn;
    }
  });

  testWidgets('a stack equal to the reference is capped, not unbounded',
      (tester) async {
    final atRef = await chipsDrawn(tester, amount: 200000, reference: 200000);
    final overRef = await chipsDrawn(tester, amount: 900000, reference: 200000);
    // An all-in monster cannot grow past the graphic.
    expect(overRef, atRef);
  });

  testWidgets('a busted seat draws nothing', (tester) async {
    expect(await chipsDrawn(tester, amount: 0, reference: 100000), 0);
  });

  testWidgets('renders without overflowing its allotted height',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              height: 32,
              child: ChipStackView(
                amount: 1234567,
                denominations: [25, 100, 500, 1000, 5000, 25000, 100000],
                reference: 1234567,
                minDenomination: 100,
                maxHeight: 32,
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  group('chip colours', () {
    test('known denominations use the casino convention', () {
      expect(chipColorFor(25).body, const Color(0xFF2E7D32)); // green 25
      expect(chipColorFor(100).body, const Color(0xFF212121)); // black 100
      expect(chipColorFor(500).body, const Color(0xFF7B1FA2)); // purple 500
      expect(chipColorFor(1000).body, const Color(0xFFFDD835)); // yellow 1k
    });

    test('an unknown denomination falls back to the next one down', () {
      expect(chipColorFor(2000).body, chipColorFor(1000).body);
      expect(chipColorFor(300).body, chipColorFor(100).body);
    });

    test('every denomination in play has a distinct colour', () {
      final colors = {for (final d in wsop) chipColorFor(d).body};
      expect(colors.length, wsop.length);
    });
  });
}
