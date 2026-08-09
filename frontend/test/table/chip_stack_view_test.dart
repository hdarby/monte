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
    test('low denominations are the classic solids', () {
      expect(chipColorFor(1).body, const Color(0xFFF5F5F5)); // white
      expect(chipColorFor(5).body, const Color(0xFFD32F2F)); // red
      expect(chipColorFor(25).body, const Color(0xFF2E7D32)); // green
      // No edge spots at the bottom of the ladder.
      for (final d in [1, 5, 25]) {
        expect(chipColorFor(d).spot, isNull);
      }
    });

    test('high denominations carry edge spots', () {
      for (final d in [100, 500, 1000, 5000, 25000, 100000, 250000, 500000]) {
        expect(chipColorFor(d).spot, isNotNull, reason: '$d has no spot');
      }
      expect(chipColorFor(100).spot, const Color(0xFF1565C0)); // blue on black
      expect(chipColorFor(500).spot, const Color(0xFFF57C00)); // orange on purple
      expect(chipColorFor(1000).spot, const Color(0xFF757575)); // gray on yellow
    });

    test('black 100 and black 500k are told apart by their spots', () {
      // The bodies genuinely match, which is why spots are not decoration.
      expect(chipColorFor(500000).body, chipColorFor(100).body);
      expect(chipColorFor(500000).spot, isNot(chipColorFor(100).spot));
    });

    test('an unknown denomination falls back to the next one down', () {
      expect(chipColorFor(2000).body, chipColorFor(1000).body);
      expect(chipColorFor(300).body, chipColorFor(100).body);
    });

    test('every denomination in play is visually distinct', () {
      // Body alone is not enough (two blacks), so identity is body + spot.
      final seen = {
        for (final d in wsop)
          '${chipColorFor(d).body}/${chipColorFor(d).spot}',
      };
      expect(seen.length, wsop.length);
    });

    test('the rim is a darkened version of the body', () {
      for (final d in wsop) {
        final c = chipColorFor(d);
        expect(c.edge.computeLuminance(), lessThan(c.body.computeLuminance() + 0.01));
      }
    });
  });

  group('five columns, coloured by what they actually hold', () {
    Future<List<int>> columnDenoms(WidgetTester tester, int amount) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ChipStackView(
                amount: amount,
                denominations: wsop,
                reference: amount,
                minDenomination: 100,
                maxHeight: 32,
              ),
            ),
          ),
        ),
      );
      // Each column is a Tooltip labelled with its denomination.
      return find
          .descendant(
            of: find.byType(ChipStackView),
            matching: find.byType(Tooltip),
          )
          .evaluate()
          .map((e) => (e.widget as Tooltip).message ?? '')
          .map(
            (m) => m.endsWith('M')
                ? (double.parse(m.substring(0, m.length - 1)) * 1000000).round()
                : m.endsWith('k')
                ? (double.parse(m.substring(0, m.length - 1)) * 1000).round()
                : int.parse(m),
          )
          .toList();
    }

    testWidgets('a full stack uses five columns, not three', (tester) async {
      final denoms = await columnDenoms(tester, 1275000);
      expect(denoms.length, 5);
    });

    testWidgets('never exceeds five columns however mixed the stack',
        (tester) async {
      for (final amount in [1275000, 60000, 987654, 5000000]) {
        expect(
          (await columnDenoms(tester, amount)).length,
          lessThanOrEqualTo(5),
          reason: 'amount $amount used too many columns',
        );
      }
    });

    testWidgets('columns run largest denomination first', (tester) async {
      final denoms = await columnDenoms(tester, 1275000);
      final sorted = [...denoms]..sort((a, b) => b.compareTo(a));
      expect(denoms, sorted);
    });

    testWidgets('the most-held denomination gets the most chips',
        (tester) async {
      // 29,000 breaks down as 1 x 25,000 + 4 x 1,000: by *count* the 1,000s
      // dominate, so they must dominate the picture even though the single 25k
      // is worth far more. (Greedy decomposition minimises chip count, so the
      // amount has to be chosen to actually produce change.)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ChipStackView(
                amount: 29000,
                denominations: const [1000, 25000],
                reference: 29000,
                minDenomination: 1000,
                maxHeight: 32,
              ),
            ),
          ),
        ),
      );
      final tooltips = find
          .descendant(
            of: find.byType(ChipStackView),
            matching: find.byType(Tooltip),
          )
          .evaluate()
          .toList();
      // Count chips per denomination across all columns.
      final perDenom = <String, int>{};
      for (final e in tooltips) {
        final t = e.widget as Tooltip;
        final chips = find
            .descendant(of: find.byWidget(t), matching: find.byType(Container))
            .evaluate()
            .length;
        perDenom[t.message ?? ''] = (perDenom[t.message ?? ''] ?? 0) + chips;
      }
      expect(perDenom['1k'], greaterThan(perDenom['25k'] ?? 0));
    });
  });
}
