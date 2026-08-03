import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/opponent_range_read.dart';
import 'package:monte/core/domain/engine/card.dart';

RangeReadCell _cell(OpponentRangeRead r, String label) =>
    r.cells.firstWhere((c) => c.label == label);

void main() {
  List<Card> h(String a, String b) => [Card.fromCode(a), Card.fromCode(b)];

  group('super-premium down-weighting on a passive line', () {
    final limped = OpponentRangeRead.estimate(
      heroHole: h('9d', '8d'),
      board: const [],
      vpip: true,
      preflopRaiseLevel: 0,
      raisedPostflop: false,
      random: Random(1),
    );

    test('QQ+/AK are flagged unlikely and heavily down-weighted', () {
      for (final label in ['AA', 'KK', 'QQ', 'AKs', 'AKo']) {
        final c = _cell(limped, label);
        expect(c.unlikelyPremium, isTrue, reason: '$label should be flagged');
      }
      // A medium/speculative hand a limper actually plays outweighs the premiums.
      final speculative = _cell(limped, 'T9s');
      final aces = _cell(limped, 'AA');
      expect(speculative.weight, greaterThan(aces.weight * 3));
    });
  });

  group('a preflop raiser keeps the premiums', () {
    final raised = OpponentRangeRead.estimate(
      heroHole: h('9d', '8d'),
      board: const [],
      vpip: true,
      preflopRaiseLevel: 1,
      raisedPostflop: false,
      random: Random(1),
    );

    test('super-premiums are strong and not flagged; trash is thin', () {
      final aces = _cell(raised, 'AA');
      expect(aces.unlikelyPremium, isFalse);
      expect(aces.weight, greaterThan(0.8));
      expect(_cell(raised, '72o').weight, lessThan(0.15));
    });
  });

  test('a 3-bet collapses the range toward premiums', () {
    final threeBet = OpponentRangeRead.estimate(
      heroHole: h('9d', '8d'),
      board: const [],
      vpip: true,
      preflopRaiseLevel: 2,
      raisedPostflop: false,
      random: Random(1),
    );
    // Premiums are firmly in; a 3-bet does NOT flag them unlikely.
    expect(_cell(threeBet, 'AA').unlikelyPremium, isFalse);
    expect(_cell(threeBet, 'AA').weight, greaterThan(0.9));
    // Hands a plain opener plays but a 3-bettor usually doesn't are thin.
    expect(_cell(threeBet, 'KTs').weight, lessThan(0.5));
    // And the 3-bet range is tighter than a flat open at the margins.
    final open = OpponentRangeRead.estimate(
      heroHole: h('9d', '8d'),
      board: const [],
      vpip: true,
      preflopRaiseLevel: 1,
      raisedPostflop: false,
      random: Random(1),
    );
    expect(_cell(threeBet, 'A9s').weight, lessThan(_cell(open, 'A9s').weight));
  });

  test('early position is tighter than late for the same open', () {
    OpponentRangeRead open(RangePosition pos) => OpponentRangeRead.estimate(
          heroHole: h('9d', '8d'),
          board: const [],
          vpip: true,
          preflopRaiseLevel: 1,
          raisedPostflop: false,
          position: pos,
          random: Random(1),
        );
    // A marginal opener (KTo) is played less from early position than late.
    expect(_cell(open(RangePosition.early), 'KTo').weight,
        lessThan(_cell(open(RangePosition.late), 'KTo').weight));
  });

  test('ahead/behind reflects the board vs the hero', () {
    // Hero flops top set with 99 on 9-6-2.
    final r = OpponentRangeRead.estimate(
      heroHole: h('9d', '9c'),
      board: [Card.fromCode('9h'), Card.fromCode('6s'), Card.fromCode('2c')],
      vpip: true,
      preflopRaiseLevel: 0,
      raisedPostflop: false,
      random: Random(3),
    );
    // The hero's set beats essentially everything: no live class should be a
    // confident favourite over top set (allow the odd coin-flip draw as split).
    final behind = r.cells.where((c) => c.combos > 0 && c.stance == RangeStance.behind);
    expect(behind, isEmpty);
    // And plenty of the opponent's holdings are behind (hero ahead).
    expect(r.cells.where((c) => c.stance == RangeStance.ahead).length,
        greaterThan(100));
  });

  test('every one of the 169 classes is present', () {
    final r = OpponentRangeRead.estimate(
      heroHole: h('As', 'Kh'),
      board: const [],
      vpip: false,
      preflopRaiseLevel: 0,
      raisedPostflop: false,
      random: Random(1),
    );
    expect(r.cells.length, 169);
    expect(r.note, contains('any two cards'));
  });
}
