import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/chip_breakdown.dart';
import 'package:monte/core/presentation/widgets/chip_stack_view.dart';
import 'package:monte/features/tournament/domain/chip_set.dart';

/// The graphic draws the chips a player is actually holding — the same spread
/// the hover legend counts. It used to scale height against the chip leader
/// instead, which made the picture and its own legend disagree by construction.
void main() {
  final wsop = ChipSet.wsop().denominations;

  Future<int> chipsDrawn(
    WidgetTester tester, {
    required int amount,
    int minDenomination = 100,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ChipStackView(
              amount: amount,
              denominations: wsop,
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

  testWidgets('draws exactly the chips the breakdown says are held',
      (tester) async {
    // The invariant that replaced height-scaling: what is drawn is what the
    // legend counts. Anything else and the two disagree in front of the user.
    const amount = 60000;
    final expected = ChipBreakdown.of(
      amount,
      denominations: wsop,
      minDenomination: 100,
      maxColumns: ChipStackView.defaultMaxColumns,
    );
    expect(await chipsDrawn(tester, amount: amount), expected.chipCount);
  });

  testWidgets('a bigger stack shows a bigger top denomination', (tester) async {
    // Size is carried by colour, not height: only a monster has a plaque in it.
    Future<int> topDenom(int amount) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ChipStackView(
                amount: amount,
                denominations: wsop,
                minDenomination: 100,
              ),
            ),
          ),
        ),
      );
      return find
          .descendant(
            of: find.byType(ChipStackView),
            matching: find.byType(ChipColumnView),
          )
          .evaluate()
          .map((e) => (e.widget as ChipColumnView).denomination)
          .reduce((a, b) => a > b ? a : b);
    }

    expect(await topDenom(2000000), greaterThan(await topDenom(120000)));
    expect(await topDenom(120000), greaterThan(await topDenom(8000)));
  });

  testWidgets('a busted seat draws nothing', (tester) async {
    expect(await chipsDrawn(tester, amount: 0), 0);
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
      for (final d in [500, 1000, 5000, 25000, 100000, 250000, 500000]) {
        expect(chipColorFor(d).spot, isNotNull, reason: '$d has no spot');
      }
      expect(chipColorFor(500).spot, const Color(0xFFF57C00)); // orange on purple
      expect(chipColorFor(1000).spot, const Color(0xFF757575)); // gray on yellow
    });

    test('black 100 and black 500k are told apart by the spots on one of them',
        () {
      // The bodies genuinely match. Spotting both blacks and relying on the
      // spot *colour* asks too much of a 3px-tall slab seen edge-on, so the
      // 100 is left solid: the cheapest chip on the table is the plain one.
      expect(chipColorFor(500000).body, chipColorFor(100).body);
      expect(chipColorFor(100).spot, isNull);
      expect(chipColorFor(500000).spot, isNotNull);
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

  group('four columns, coloured by what they actually hold', () {
    Future<List<int>> columnDenoms(WidgetTester tester, int amount) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ChipStackView(
                amount: amount,
                denominations: wsop,
                minDenomination: 100,
                maxHeight: 32,
              ),
            ),
          ),
        ),
      );
      // Each column exposes the denomination it is made of.
      return find
          .descendant(
            of: find.byType(ChipStackView),
            matching: find.byType(ChipColumnView),
          )
          .evaluate()
          .map((e) => (e.widget as ChipColumnView).denomination)
          .toList();
    }

    testWidgets('a full stack spreads over four denominations, not one',
        (tester) async {
      expect((await columnDenoms(tester, 1275000)).length, 4);
    });

    testWidgets('never exceeds four columns however mixed the stack',
        (tester) async {
      for (final amount in [1275000, 60000, 987654, 5000000]) {
        expect(
          (await columnDenoms(tester, amount)).length,
          lessThanOrEqualTo(4),
          reason: 'amount $amount used too many columns',
        );
      }
    });

    testWidgets('a stack worth less than one chip draws exactly one chip',
        (tester) async {
      // The breakdown has to name *some* denomination for a stack below the
      // smallest chip on the table, and it must stay a single chip — scaling
      // that fallback is what let a 60,000 stack render as several columns of
      // 500,000 chips.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ChipStackView(
                amount: 60000,
                denominations: wsop, // chip leader, so the height scale is maximal
                minDenomination: 500000,
                maxHeight: 32,
              ),
            ),
          ),
        ),
      );
      final chips = find
          .descendant(
            of: find.byType(ChipStackView),
            matching: find.byType(Container),
          )
          .evaluate()
          .length;
      expect(chips, 1, reason: 'less than one chip is one chip, not a tower');
    });

    testWidgets('never draws a denomination bigger than the stack itself',
        (tester) async {
      for (final amount in [3000, 60000, 275000, 1200000]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: ChipStackView(
                  amount: amount,
                  denominations: wsop,
                  minDenomination: 1000,
                  maxHeight: 32,
                ),
              ),
            ),
          ),
        );
        final drawn = find
            .descendant(
              of: find.byType(ChipStackView),
              matching: find.byType(ChipColumnView),
            )
            .evaluate()
            .map((e) => (e.widget as ChipColumnView).denomination);
        for (final d in drawn) {
          expect(d, lessThanOrEqualTo(amount),
              reason: 'a $amount stack cannot hold a $d chip');
        }
      }
    });

    testWidgets('columns run largest denomination first', (tester) async {
      final denoms = await columnDenoms(tester, 1275000);
      final sorted = [...denoms]..sort((a, b) => b.compareTo(a));
      expect(denoms, sorted);
    });

    testWidgets('the drawn counts are the counts the legend prints',
        (tester) async {
      // This test used to assert a *re-allocation* of the chips — first by
      // count, then by value share — because the view scaled the stack to a
      // height rather than drawing it. Either way the picture was not the
      // player's chips, and the legend beside it said something else.
      const amount = 239400;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ChipStackView(
                amount: amount,
                denominations: wsop,
                minDenomination: 100,
                maxHeight: 60,
              ),
            ),
          ),
        ),
      );
      final perDenom = <int, int>{};
      for (final e in find
          .descendant(
            of: find.byType(ChipStackView),
            matching: find.byType(ChipColumnView),
          )
          .evaluate()) {
        final c = e.widget as ChipColumnView;
        perDenom[c.denomination] =
            (perDenom[c.denomination] ?? 0) + c.column.count;
      }
      final expected = {
        for (final c in ChipBreakdown.of(
          amount,
          denominations: wsop,
          minDenomination: 100,
          maxColumns: ChipStackView.defaultMaxColumns,
        ).columns)
          c.denomination: c.count,
      };
      expect(perDenom, expected);
    });
  });

  // The seat gives the graphic a fixed width (`_cardWidth * 2 + 4` in
  // PlayerSeat), so adding columns can silently overflow it. These pin the
  // widths the seat actually passes.
  group('four columns fit the seat they are drawn in', () {
    // The seat derives its width from the hole cards: _cardWidth * 2 + 4.
    Future<double> renderedWidth(WidgetTester tester,
        {required double chipWidth, required double maxHeight}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: ChipStackView(
              amount: 1275000,
              denominations: wsop,
              minDenomination: 100,
              maxHeight: maxHeight,
              chipWidth: chipWidth,
            ),
          ),
        ),
      ));
      return tester.getSize(find.byType(ChipStackView)).width;
    }

    testWidgets('the normal seat has room for the wider chip', (tester) async {
      final w = await renderedWidth(tester, chipWidth: 13, maxHeight: 32);
      expect(w, lessThanOrEqualTo(60.0 * 2 + 4));
    });

    testWidgets('the compact seat has room for the wider chip', (tester) async {
      final w = await renderedWidth(tester, chipWidth: 10, maxHeight: 22);
      expect(w, lessThanOrEqualTo(34.0 * 2 + 4));
    });
  });
}
