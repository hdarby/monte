import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/open_sizing.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

/// Effective stack depth in BB, given a chip stack at 1/2 blinds.
const _bb = 2;

PokerGame _game({
  required int stack,
  int players = 6,
  int ante = 0,
}) {
  final ps = [
    for (var i = 0; i < players; i++)
      Player(id: 'p$i', name: 'p$i', stack: stack),
  ];
  return PokerGame(
    players: ps,
    deck: Deck(),
    smallBlind: 1,
    bigBlind: _bb,
    ante: ante,
  );
}

void main() {
  group('OpenSizing.baseForDepth', () {
    test('is monotonically increasing in depth', () {
      var prev = 0.0;
      for (final d in [5.0, 15.0, 25.0, 40.0, 60.0, 100.0, 150.0, 250.0, 500.0]) {
        final v = OpenSizing.baseForDepth(d);
        expect(v, greaterThanOrEqualTo(prev),
            reason: 'open size must not shrink as stacks get deeper (at $d bb)');
        prev = v;
      }
    });

    test('lands on published anchors', () {
      expect(OpenSizing.baseForDepth(25), closeTo(2.4, 0.001));
      expect(OpenSizing.baseForDepth(100), closeTo(3.5, 0.001));
      expect(OpenSizing.baseForDepth(400), closeTo(3.9, 0.001));
    });

    test('clamps outside the anchor range instead of extrapolating', () {
      expect(OpenSizing.baseForDepth(3), closeTo(2.2, 0.001));
      expect(OpenSizing.baseForDepth(5000), closeTo(3.9, 0.001));
      // Infinite depth is the *deepest* case, not the shallowest — folding it
      // in with NaN under one `!isFinite` guard made it open the minimum.
      expect(OpenSizing.baseForDepth(double.infinity), closeTo(3.9, 0.001));
      expect(OpenSizing.baseForDepth(double.nan), closeTo(3.5, 0.001));
    });

    test('interpolates in log depth, not linear depth', () {
      // The midpoint of 100..400 in *log* space is 200, so the value there is
      // the average of the two endpoints. Linear interpolation would put the
      // average at 250 instead. This is the property that makes a doubling of
      // stack matter the same amount everywhere.
      final mid = (OpenSizing.baseForDepth(100) + OpenSizing.baseForDepth(400)) / 2;
      expect(OpenSizing.baseForDepth(200), closeTo(mid, 0.001));
    });
  });

  group('OpenSizing.openToBb', () {
    test('a 100bb cash open is ~3.5bb, not the old constant 2.75', () {
      expect(OpenSizing.openToBb(depthBb: 100), closeTo(3.5, 0.01));
    });

    test('antes make the open SMALLER, not larger', () {
      // The bug this model exists to fix: the old pot-fraction formula opened
      // 2.75bb in cash and 3.25bb with a big-blind ante — backwards.
      final noAnte = OpenSizing.openToBb(depthBb: 40);
      final withAnte = OpenSizing.openToBb(depthBb: 40, deadMoneyBb: 2.5);
      expect(withAnte, lessThan(noAnte));
      expect(noAnte - withAnte, closeTo(0.4, 0.01));
    });

    test('tournament depth with an ante still opens near 2.2bb', () {
      // Live-cash anchors must not drag tournament sizing up with them: the
      // ante discount is what keeps a 30bb anted open at a sane 2.2x.
      expect(OpenSizing.openToBb(depthBb: 30, deadMoneyBb: 2.5),
          closeTo(2.2, 0.2));
    });

    test('deep no-ante opens materially larger than shallow with an ante', () {
      final deepCash = OpenSizing.openToBb(depthBb: 250);
      final shallowMtt = OpenSizing.openToBb(depthBb: 25, deadMoneyBb: 2.5);
      expect(deepCash - shallowMtt, greaterThan(1.0));
    });

    test('adds a big blind per limper, capped', () {
      final base = OpenSizing.openToBb(depthBb: 100);
      expect(OpenSizing.openToBb(depthBb: 100, limpers: 1),
          closeTo(base + 1.0, 0.01));
      expect(OpenSizing.openToBb(depthBb: 100, limpers: 2),
          closeTo(base + 2.0, 0.01));
      // Six limpers must not produce a 9bb open — but three of them must still
      // get charged for in full. The ceiling has to sit above
      // `deepest anchor + max limpers`, or it eats the limper term instead of
      // catching a runaway formula.
      expect(OpenSizing.openToBb(depthBb: 100, limpers: 6),
          closeTo(base + 3.0, 0.01));
      expect(OpenSizing.openToBb(depthBb: 400, limpers: 3),
          closeTo(3.9 + 3.0, 0.01));
    });

    test('never returns an illegal or absurd size', () {
      for (final depth in [1.0, 10.0, 100.0, 1000.0]) {
        for (final dead in [1.5, 2.5, 4.5]) {
          for (final limp in [0, 3, 9]) {
            final v = OpenSizing.openToBb(
                depthBb: depth, deadMoneyBb: dead, limpers: limp);
            expect(v, inInclusiveRange(2.0, 8.0));
          }
        }
      }
    });
  });

  group('OpenSizing.raiseToFor', () {
    test('reads depth off the real game and sizes in chips', () {
      final g = _game(stack: 200); // 100 bb at 1/2
      g.startHand();
      final p = g.currentPlayer!;
      final to = OpenSizing.raiseToFor(g, p);
      // ~3.5 bb, snapped to a human denomination.
      expect(to / _bb, closeTo(3.5, 0.6));
      expect(to, greaterThanOrEqualTo(g.minRaiseTo(p)));
      expect(to, lessThanOrEqualTo(g.maxRaiseTo(p)));
    });

    test('a short stack opens smaller than a deep one', () {
      final shallow = _game(stack: 40); // 20 bb
      final deep = _game(stack: 500); // 250 bb
      shallow.startHand();
      deep.startHand();
      final s = OpenSizing.raiseToFor(shallow, shallow.currentPlayer!) / _bb;
      final d = OpenSizing.raiseToFor(deep, deep.currentPlayer!) / _bb;
      expect(s, lessThan(d));
    });

    test('an ante shrinks the open at the same depth', () {
      final plain = _game(stack: 200);
      final anted = _game(stack: 200, ante: _bb);
      plain.startHand();
      anted.startHand();
      final a = OpenSizing.raiseToFor(plain, plain.currentPlayer!);
      final b = OpenSizing.raiseToFor(anted, anted.currentPlayer!);
      expect(b, lessThanOrEqualTo(a));
    });

    test('the ante is dead money, not a limper — no double counting', () {
      // With a big-blind ante the pot is 2.5bb before anyone acts. If the ante
      // were mistaken for limper chips the open would grow by a full BB instead
      // of shrinking, which is the exact failure mode this guards.
      final anted = _game(stack: 200, ante: _bb);
      anted.startHand();
      final p = anted.currentPlayer!;
      expect(OpenSizing.limperCount(anted, p), 0);
      expect(OpenSizing.raiseToFor(anted, p) / _bb, lessThan(3.5));
    });

    test('degrades to a min-raise when there is no big blind', () {
      final g = _game(stack: 200);
      g.startHand();
      final p = g.currentPlayer!;
      // Defensive path: nothing should divide by zero.
      expect(() => OpenSizing.raiseToFor(g, p), returnsNormally);
    });

    group('sizeScale (personality)', () {
      test('an aggressive personality opens bigger than a nitty one', () {
        final g = _game(stack: 200);
        g.startHand();
        final p = g.currentPlayer!;
        final nit = OpenSizing.raiseToFor(g, p, sizeScale: 0.6);
        final base = OpenSizing.raiseToFor(g, p, sizeScale: 1.0);
        final maniac = OpenSizing.raiseToFor(g, p, sizeScale: 1.6);
        expect(nit, lessThan(base));
        expect(base, lessThan(maniac));
      });

      test('never scales below the legal minimum, however nitty', () {
        final g = _game(stack: 200);
        g.startHand();
        final p = g.currentPlayer!;
        final to = OpenSizing.raiseToFor(g, p, sizeScale: 0.1);
        expect(to, greaterThanOrEqualTo(g.minRaiseTo(p)));
      });
    });

    group('jitter', () {
      test('is bounded and roughly zero-mean over many seeds', () {
        final g = _game(stack: 200);
        g.startHand();
        final p = g.currentPlayer!;
        final base = OpenSizing.raiseToFor(g, p);
        final samples = [
          for (var seed = 0; seed < 300; seed++)
            OpenSizing.raiseToFor(g, p, random: Random(seed)) - base,
        ];
        final meanDrift = samples.reduce((a, b) => a + b) / samples.length;
        expect(meanDrift.abs(), lessThan(base * 0.05),
            reason: 'jitter must not secretly shift calibration one way');
        for (final s in samples) {
          expect(s.abs(), lessThanOrEqualTo(_bb * 2),
              reason: 'jitter must stay small relative to the blind');
        }
      });

      test('omitting random keeps the size fully deterministic', () {
        final g = _game(stack: 200);
        g.startHand();
        final p = g.currentPlayer!;
        expect(OpenSizing.raiseToFor(g, p), OpenSizing.raiseToFor(g, p));
      });
    });
  });
}
