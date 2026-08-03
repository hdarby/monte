import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/tournament/domain/chip_set.dart';

void main() {
  final chips = ChipSet.wsop();

  group('smallestChip', () {
    test('is the largest denom dividing every active betting unit', () {
      // 100/100, no ante -> 100 divides both; 25 also does, but 100 is larger.
      expect(chips.smallestChip(smallBlind: 100, bigBlind: 100, ante: 0), 100);
      // 300/500/500 -> 100 divides all three (300=3x100); 500 does not (300).
      expect(chips.smallestChip(smallBlind: 300, bigBlind: 500, ante: 500), 100);
      // 150/250/250 -> not multiples of 100, but all multiples of 25.
      expect(chips.smallestChip(smallBlind: 150, bigBlind: 250, ante: 250), 25);
      // 500/1000/1000 -> 500 divides all.
      expect(
          chips.smallestChip(smallBlind: 500, bigBlind: 1000, ante: 1000), 500);
      // Deep late level: 25000 divides 50k/100k (100000 not); so unit=25000.
      expect(
          chips.smallestChip(
              smallBlind: 50000, bigBlind: 100000, ante: 100000),
          25000);
    });

    test('rises monotonically as blinds climb (color-ups only remove chips)', () {
      final ladder = [
        [100, 100, 0],
        [200, 400, 400],
        [500, 1000, 1000],
        [2000, 4000, 4000],
        [25000, 50000, 50000],
      ];
      var prev = 0;
      for (final l in ladder) {
        final u = chips.smallestChip(
            smallBlind: l[0], bigBlind: l[1], ante: l[2]);
        expect(u, greaterThanOrEqualTo(prev));
        prev = u;
      }
    });
  });

  group('colorUp', () {
    test('conserves total chips exactly', () {
      final stacks = {'a': 1325, 'b': 4075, 'c': 900, 'd': 12200};
      final before = stacks.values.fold(0, (s, v) => s + v);
      final deltas = chips.colorUp(stacks, 500);
      final after = stacks.entries
          .fold(0, (s, e) => s + e.value + deltas[e.key]!);
      expect(after, before);
    });

    test('every resulting stack is a multiple of the new unit', () {
      final stacks = {'a': 1325, 'b': 4075, 'c': 900, 'd': 12200};
      final deltas = chips.colorUp(stacks, 500);
      for (final e in stacks.entries) {
        expect((e.value + deltas[e.key]!) % 500, 0);
      }
    });

    test('largest odd remainder wins the raced chip', () {
      // a: rem 400, b: rem 100 (of 500). One chip to award (400+100=500).
      final deltas = chips.colorUp({'a': 400, 'b': 100}, 500);
      expect(deltas['a'], 100); // -400 + 500
      expect(deltas['b'], -100); // raced off, won nothing
    });

    test('conserves total exactly even when it is not a multiple of the unit', () {
      // 1250 + 300 = 1550; odd chips exist (a chopped pot left them). Nothing
      // may be destroyed.
      final stacks = {'a': 1250, 'b': 300};
      final before = stacks.values.fold(0, (s, v) => s + v);
      final deltas = chips.colorUp(stacks, 500);
      final after =
          stacks.entries.fold(0, (s, e) => s + e.value + deltas[e.key]!);
      expect(after, before);
    });

    test('exact multiples are untouched', () {
      final deltas = chips.colorUp({'a': 1000, 'b': 2000}, 500);
      expect(deltas['a'], 0);
      expect(deltas['b'], 0);
    });
  });
}
