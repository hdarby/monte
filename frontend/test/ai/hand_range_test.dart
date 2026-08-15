import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/hand_range.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';

import '../_helpers.dart';

bool _holds(HandRange r, List<Card> hand) => r.combos.any(
      (c) =>
          (c.$1 == hand[0] && c.$2 == hand[1]) ||
          (c.$1 == hand[1] && c.$2 == hand[0]),
    );

void main() {
  group('HandRange.polarisedOn', () {
    final board = cards('Kh 8s 3c 4d 2h');

    // What the policy actually feeds in: a preflop-plausible range already
    // narrowed for having reached the river.
    HandRange source() =>
        HandRange.top(0.40, dead: board.toSet())
            .narrowedBy(street: BettingRound.river);

    test('keeps value and air but drops the middle of the range', () {
      final src = source();
      final range = src.polarisedOn(board, bluffFraction: 0.30);
      expect(range.length, lessThan(src.length));

      // Polarised means non-contiguous by strength: everything dropped sits
      // *between* the weakest hand kept for value and the strongest bluff.
      final kept = range.combos
          .map((c) => HandEvaluator.evaluate([c.$1, c.$2, ...board]))
          .toList()
        ..sort();
      final dropped = src.combos
          .where((c) => !_holds(range, [c.$1, c.$2]))
          .map((c) => HandEvaluator.evaluate([c.$1, c.$2, ...board]))
          .toList();
      expect(dropped, isNotEmpty);

      // A polarised range has a gap: some kept hand is weaker than every
      // dropped hand (the bluffs) and some is stronger (the value).
      expect(kept.first.compareTo(dropped.reduce((a, b) => a < b ? a : b)),
          lessThan(0),
          reason: 'the bluff tail is weaker than anything checked back');
      expect(kept.last.compareTo(dropped.reduce((a, b) => a > b ? a : b)),
          greaterThan(0),
          reason: 'the value half is stronger than anything checked back');
    });

    test('a bigger assumed bluff share admits more air', () {
      // A narrow betting range, so the value slice is actually tighter than the
      // number of made hands available — at the default width both slices
      // contain every made hand and the comparison says nothing.
      final tight =
          source().polarisedOn(board, bluffFraction: 0.05, betRangeFraction: 0.35);
      final loose =
          source().polarisedOn(board, bluffFraction: 0.40, betRangeFraction: 0.35);

      // Count *made* hands rather than air: on a dry board a preflop-strong
      // range is mostly unpaired either way, so the air count saturates and
      // says nothing. The made-hand count is the quantity that actually moves.
      int madeIn(HandRange r) => r.combos
          .where((c) =>
              HandEvaluator.evaluate([c.$1, c.$2, ...board]).rank !=
              HandRank.highCard)
          .length;

      expect(madeIn(loose), lessThan(madeIn(tight)),
          reason: 'assuming more bluffs must mean fewer value hands');
      // The overall betting range is the same size — only its makeup shifts.
      expect(loose.length, tight.length);
    });

    test('is a no-op preflop, where there is no board to read', () {
      final pre = HandRange.top(0.4);
      expect(pre.polarisedOn(const [], bluffFraction: 0.3).length, pre.length);
    });

    test('a narrower betting range leaves a bluff-catcher behind', () {
      // The whole point: how much of a betting range a marginal hand beats has
      // to fall as that range narrows toward value. (The absolute number is
      // board-dependent — a strong preflop range misses a K-8-3-4-2 badly — so
      // this asserts the direction, and the calibrated frequencies are gated in
      // test/ai/postflop_discipline_test.dart.)
      double beatShare(double width) {
        final range = source().polarisedOn(board,
            bluffFraction: 0.25, betRangeFraction: width);
        final hero = HandEvaluator.evaluate([...cards('9c 9d'), ...board]);
        final beaten = range.combos
            .where((c) =>
                hero.compareTo(HandEvaluator.evaluate([c.$1, c.$2, ...board])) >
                0)
            .length;
        return beaten / range.length;
      }

      expect(beatShare(0.35), lessThan(beatShare(0.85)),
          reason: 'a value-heavy range leaves third pair further behind');
      expect(beatShare(0.35), lessThan(0.4),
          reason: 'against a narrow value range a bluff-catcher is drawing thin');
    });
  });
}
