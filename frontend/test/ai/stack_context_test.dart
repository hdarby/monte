import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/stack_context.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

StackContext _ctx({
  required int effectiveStart,
  required int behind,
  required int pot,
  int bigBlind = 200,
  int streetsRemaining = 2,
}) =>
    StackContext(
      effectiveStart: effectiveStart,
      behind: behind,
      pot: pot,
      bigBlind: bigBlind,
      streetsRemaining: streetsRemaining,
    );

void main() {
  group('regimes', () {
    test('depth bands run push-fold through very deep', () {
      expect(StackRegime.forDepth(8), StackRegime.pushFold);
      expect(StackRegime.forDepth(20), StackRegime.short);
      expect(StackRegime.forDepth(100), StackRegime.normal);
      expect(StackRegime.forDepth(200), StackRegime.deep);
      // Main Event level 1: 60,000 at 100/200.
      expect(StackRegime.forDepth(300), StackRegime.veryDeep);
    });

    test('SPR bands run committed through very high', () {
      expect(SprBand.forSpr(0.5), SprBand.committed);
      expect(SprBand.forSpr(2), SprBand.low);
      expect(SprBand.forSpr(5), SprBand.medium);
      expect(SprBand.forSpr(10), SprBand.high);
      expect(SprBand.forSpr(40), SprBand.veryHigh);
    });
  });

  group('depth is a hand-level constant, SPR is not', () {
    test('depth is read from the start-of-hand stack, not what is left', () {
      // Same player, same hand: 300 BB to start, but 200 BB already committed.
      final early = _ctx(effectiveStart: 60000, behind: 60000, pot: 600);
      final late = _ctx(effectiveStart: 60000, behind: 20000, pot: 80000);
      expect(early.depthBb, late.depthBb,
          reason: 'how deep the game is cannot change mid-hand');
      expect(late.regime, StackRegime.veryDeep);
    });

    test('SPR falls as the pot grows — that is the point', () {
      final early = _ctx(effectiveStart: 60000, behind: 60000, pot: 600);
      final late = _ctx(effectiveStart: 60000, behind: 20000, pot: 80000);
      expect(early.spr, greaterThan(late.spr));
      expect(early.sprBand, SprBand.veryHigh);
      expect(late.sprBand, SprBand.committed);
    });

    test('reads both numbers off a real game', () {
      final order = [
        for (final s in Suit.values)
          for (final r in Rank.values) Card(r, s),
      ];
      final g = PokerGame(
        players: [
          Player(id: 'p0', name: 'P0', stack: 60000),
          Player(id: 'p1', name: 'P1', stack: 60000, isHuman: true),
        ],
        deck: Deck.stacked(order),
        smallBlind: 100,
        bigBlind: 200,
      )..startHand();
      final c = StackContext.of(g, g.players.first);
      expect(c.depthBb, closeTo(300, 0.01));
      expect(c.regime, StackRegime.veryDeep);
      expect(c.streetsRemaining, 3);
    });
  });

  group('geometric sizing', () {
    test('gets exactly all-in over the remaining streets', () {
      // Bet f*pot, get called, repeat: verify the stack lands at zero.
      for (final spr in [1.0, 3.0, 8.0, 40.0]) {
        for (final n in [1, 2, 3]) {
          const pot = 1000;
          final behind = (spr * pot).round();
          final c = _ctx(
              effectiveStart: behind, behind: behind, pot: pot,
              streetsRemaining: n);
          final f = c.geometricFraction();
          var p = pot.toDouble();
          var left = behind.toDouble();
          for (var i = 0; i < n; i++) {
            final bet = f * p;
            left -= bet;
            p += 2 * bet;
          }
          expect(left, closeTo(0, pot * 0.02),
              reason: 'spr $spr over $n streets did not land on a stack-off');
        }
      }
    });

    test('deep, a stack-off demands an absurd size — which is the lesson', () {
      // 300 BB deep in a small pot: you cannot get stacks in without overbetting
      // wildly, so one pair simply must not try.
      final deep = _ctx(effectiveStart: 60000, behind: 60000, pot: 1500,
          streetsRemaining: 3);
      expect(deep.geometricFraction(), greaterThan(1.5));

      // At a normal SPR it is an ordinary half-pot-ish bet.
      final normal = _ctx(effectiveStart: 4000, behind: 4000, pot: 1000,
          streetsRemaining: 3);
      expect(normal.geometricFraction(), closeTo(0.54, 0.1));
    });
  });

  group('pot control sizing', () {
    test('keeps the SPR above the floor once called', () {
      final c = _ctx(effectiveStart: 60000, behind: 60000, pot: 1500);
      const floor = 8.0;
      final f = c.potControlFraction(floor);
      final bet = f * c.pot;
      final newPot = c.pot + 2 * bet;
      final newBehind = c.behind - bet;
      expect(newBehind / newPot, greaterThanOrEqualTo(floor - 0.01));
    });

    test('is smaller than the stack-off size whenever one is possible', () {
      final c = _ctx(effectiveStart: 60000, behind: 60000, pot: 1500,
          streetsRemaining: 2);
      expect(c.potControlFraction(8), lessThan(c.geometricFraction()));
    });

    test('goes to zero when the pot is already too big to control', () {
      final c = _ctx(effectiveStart: 60000, behind: 3000, pot: 20000);
      expect(c.potControlFraction(8), 0.0,
          reason: 'no bet keeps the SPR high here — check instead');
    });
  });
}
