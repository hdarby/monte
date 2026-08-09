import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/table/domain/table_snapshot.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';
import 'package:monte/features/table/data/table_snapshot_projection.dart';
import 'package:monte/features/tournament/domain/chip_set.dart';

/// In a tournament every wager must be a whole number of the smallest chip in
/// play. The slider and the pot-fraction presets have to respect that, or the
/// UI shows an amount the engine will not actually wager.
ActionContext ctx({
  int chipUnit = 100,
  int minRaiseTo = 200,
  int maxRaiseTo = 60000,
  int currentBet = 100,
}) => ActionContext(
  callAmount: 0,
  canCheck: false,
  minRaiseTo: minRaiseTo,
  maxRaiseTo: maxRaiseTo,
  bigBlind: 100,
  currentBet: currentBet,
  chipUnit: chipUnit,
);

void main() {
  group('snapRaise', () {
    test('a third-pot bet at a 100/100 level becomes 100, never 33', () {
      // pot 100, a third of it is 33.3 — not a legal amount with 100 chips.
      expect(ctx(minRaiseTo: 100).snapRaise(33), 100);
    });

    test('rounds to the nearest whole chip', () {
      final c = ctx();
      expect(c.snapRaise(1240), 1200);
      expect(c.snapRaise(1260), 1300);
      expect(c.snapRaise(1250), 1300); // .5 rounds up
    });

    test('never returns an illegal amount below the minimum raise', () {
      final c = ctx(minRaiseTo: 250, chipUnit: 100);
      final snapped = c.snapRaise(10);
      expect(snapped, greaterThanOrEqualTo(250));
      // and it is still chip-aligned
      expect(snapped % 100, 0);
    });

    test('rounds the minimum up, not down, when it is not chip-aligned', () {
      // A 250 minimum with 100-chips must become 300, not 200.
      expect(ctx(minRaiseTo: 250, chipUnit: 100).snapRaise(250), 300);
    });

    test('all-in stays exact even when the stack is not a clean multiple', () {
      // Matches the engine, which exempts maxRaiseTo from snapping.
      final c = ctx(chipUnit: 500, maxRaiseTo: 61234);
      expect(c.snapRaise(61234), 61234);
      expect(c.snapRaise(99999), 61234);
    });

    test('clamps above the maximum to the all-in amount', () {
      expect(ctx(maxRaiseTo: 5000).snapRaise(1 << 30), 5000);
    });

    test('a chip unit of 1 (cash game) leaves amounts untouched', () {
      final c = ctx(chipUnit: 1, minRaiseTo: 20, maxRaiseTo: 1000);
      expect(c.snapRaise(37), 37);
      expect(c.snapRaise(43), 43);
    });

    test('every snapped value in the range is chip-aligned', () {
      final c = ctx(chipUnit: 500, minRaiseTo: 1000, maxRaiseTo: 50000);
      for (var target = 1000; target < 50000; target += 137) {
        final snapped = c.snapRaise(target);
        expect(
          snapped % 500,
          0,
          reason: 'target $target snapped to $snapped, not a multiple of 500',
        );
        expect(snapped, greaterThanOrEqualTo(1000));
        expect(snapped, lessThanOrEqualTo(50000));
      }
    });
  });

  group('raiseSteps', () {
    test('gives one slider stop per chip increment', () {
      expect(ctx(chipUnit: 100, minRaiseTo: 200, maxRaiseTo: 1200).raiseSteps, 10);
    });

    test('is at least 1 even when the player is already all-in-or-nothing', () {
      expect(ctx(minRaiseTo: 500, maxRaiseTo: 500).raiseSteps, 1);
    });

    test('stays sane for a huge stack with tiny chips', () {
      final steps = ctx(chipUnit: 1, minRaiseTo: 1, maxRaiseTo: 100000000)
          .raiseSteps;
      expect(steps, lessThanOrEqualTo(1 << 20));
    });
  });

  group('end to end: the chip unit reaches the UI', () {
    test('a 100/100 Main Event level puts nothing smaller than a 100 chip in play',
        () {
      final chips = ChipSet.wsop();
      final unit = chips.smallestChip(smallBlind: 100, bigBlind: 100, ante: 0);
      expect(unit, greaterThan(1));
      expect(100 % unit, 0, reason: 'the blind must be payable in whole chips');
    });

    test('the projection hands the engine chip unit to the action context', () {
      final game = PokerGame(
        players: [
          Player(id: 'you', name: 'You', stack: 60000, isHuman: true),
          Player(id: 'b1', name: 'Bot', stack: 60000),
        ],
        smallBlind: 100,
        bigBlind: 100,
        chipUnit: 100,
      )..startHand();

      final snap = projectTableSnapshot(game);
      final ctx = snap.actionContext;
      // Only assert when it is actually the human's turn to act.
      if (ctx != null) {
        expect(ctx.chipUnit, 100);
        // The bug this fixes: a third of a 200 pot is 66, which is not payable.
        expect(ctx.snapRaise(66) % 100, 0);
        expect(ctx.snapRaise(33), greaterThanOrEqualTo(ctx.minRaiseTo));
      }
    });
  });
}
