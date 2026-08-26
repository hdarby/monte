import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/icm_adjusted_decider.dart';
import 'package:monte/core/domain/ai/push_fold_chart.dart';
import 'package:monte/core/domain/ai/tournament_context.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

import '../../_helpers.dart';

// Hero is the button in a 3-handed hand (first to act preflop), holding [hero]
// with a [stackBb]-big-blind stack; returns the game with hero on the button.
(PokerGame, Player) _short(List<Card> hero, {int stackBb = 5}) {
  const bb = 20;
  final players = [
    Player(id: 'h', name: 'H', stack: stackBb * bb),
    Player(id: 'a', name: 'A', stack: 1000),
    Player(id: 'b', name: 'B', stack: 1000),
  ];
  final g = PokerGame(
    players: players,
    smallBlind: bb ~/ 2,
    bigBlind: bb,
    deck: Deck(random: Random(1)),
  )..startHand();
  final h = g.currentPlayer!; // the button/hero acts first 3-handed
  h.hole
    ..clear()
    ..addAll(hero);
  return (g, h);
}

TournamentContext _ctx({double stackBb = 5, double bubble = 1.0}) =>
    TournamentContext(
      stackInBb: stackBb,
      bubbleFactor: bubble,
      playersLeft: 4,
      paidPlaces: 3,
      inMoney: false,
    );

class _Fixed implements DecisionPolicy {
  const _Fixed(this.action);
  final GameAction action;
  @override
  GameAction decide(PokerGame g, Player p) => action;
}

void main() {
  group('PushFoldChart', () {
    const chart = PushFoldChart();

    test('a short stack jams a premium and folds trash', () {
      final (gAces, aces) = _short(cards('As Ac'));
      expect(chart.decide(gAces, aces, _ctx()).type, ActionType.raise);

      final (gTrash, trash) = _short(cards('7c 2d'));
      expect(chart.decide(gTrash, trash, _ctx()).type, ActionType.fold);
    });

    test('the jam range tightens as the bubble factor rises', () {
      final hands = [
        'Ah 9c', 'Kd Ts', 'Qc Jd', 'Ts 9s', 'Ad 5c', 'Kh 8d',
        'Jc Td', 'Qh 9h', 'As 4d', 'Kc 9s', 'Jh Ts', 'Qd 8d',
      ].map(cards).toList();
      int jams(double bubble) {
        var n = 0;
        for (final h in hands) {
          final (g, hero) = _short(h);
          if (chart.decide(g, hero, _ctx(bubble: bubble)).type == ActionType.raise) {
            n++;
          }
        }
        return n;
      }

      expect(jams(2.0), lessThan(jams(1.0)),
          reason: 'ICM pressure narrows the shove range');
    });
  });

  group('IcmAdjustedDecider', () {
    test('near the bubble it folds a big call that it makes off the bubble', () {
      GameAction wrapped(double bubble, List<Card> hand) {
        final players = [
          Player(id: 'p0', name: 'P0', stack: 1000),
          Player(id: 'p1', name: 'P1', stack: 1000),
        ];
        final g = PokerGame(
          players: players,
          smallBlind: 10,
          bigBlind: 20,
          deck: Deck(random: Random(2)),
        )
          ..buttonIndex = 1
          ..startHand();
        g.applyAction(GameAction.raise(g.maxRaiseTo(g.currentPlayer!)));
        final hero = g.currentPlayer!; // p0 (BB), ~50bb, facing an all-in
        hero.hole
          ..clear()
          ..addAll(hand);
        final decider = IcmAdjustedDecider(
          const _Fixed(GameAction.call()),
          (game, p) => _ctx(stackBb: 50, bubble: bubble),
        );
        return decider.decide(g, hero);
      }

      const marginal = 'Kd Ts'; // not a premium — a coin-flip-ish bluff-catch
      expect(wrapped(1.0, cards(marginal)).type, ActionType.call,
          reason: 'off the bubble the inner call passes through');
      expect(wrapped(1.8, cards(marginal)).type, ActionType.fold,
          reason: 'on the bubble the big call is demoted to a fold');
    });

    test('a short stack is put on push/fold regardless of the inner brain', () {
      // Inner would call, but at 5bb preflop the chart takes over and folds trash.
      final (g, hero) = _short(cards('7c 2d'));
      final decider = IcmAdjustedDecider(
        const _Fixed(GameAction.call()),
        (game, p) => _ctx(stackBb: 5),
      );
      expect(decider.decide(g, hero).type, ActionType.fold);
    });
  });

  group('IcmAdjustedDecider survival-pressure size damping', () {
    // A deep (100bb) 6-max hand with an unopened pot, so the inner policy's
    // raise survives every existing veto (they only ever touch calls, or
    // trigger far short-stacked) and only the new damping logic can move it.
    (PokerGame, Player) deepStack() {
      final players = [
        for (var i = 0; i < 6; i++) Player(id: 'p$i', name: 'P$i', stack: 20000),
      ];
      final g = PokerGame(
        players: players,
        smallBlind: 100,
        bigBlind: 200,
        deck: Deck(random: Random(3)),
      )..startHand();
      return (g, g.currentPlayer!);
    }

    GameAction dampedRaiseTo(
      PokerGame g,
      Player hero,
      int rawTo, {
      double ladderPressure = 0,
      double bubbleFactor = 1.0,
      int playersLeft = 9,
    }) {
      final decider = IcmAdjustedDecider(
        _Fixed(GameAction.raise(rawTo)),
        (game, p) => TournamentContext(
          stackInBb: 100,
          bubbleFactor: bubbleFactor,
          playersLeft: playersLeft,
          paidPlaces: 9,
          inMoney: false,
          ladderPressure: ladderPressure,
        ),
      );
      return decider.decide(g, hero);
    }

    test('a raise is shrunk even far from the bubble, at level-1 depth', () {
      final (g, hero) = deepStack();
      final rawTo = g.minRaiseTo(hero) + 600; // a healthy open, well above min
      final damped = dampedRaiseTo(g, hero, rawTo);
      expect(damped.type, ActionType.raise);
      expect(damped.amount, lessThan(rawTo),
          reason: 'the baseline survival pressure must fire on hand one, not '
              'just near the bubble');
      expect(damped.amount, greaterThanOrEqualTo(g.minRaiseTo(hero)));
    });

    test('never damps in the cash sentinel context', () {
      final (g, hero) = deepStack();
      final rawTo = g.minRaiseTo(hero) + 600;
      final decider = IcmAdjustedDecider(
        _Fixed(GameAction.raise(rawTo)),
        (game, p) => TournamentContext.cash,
      );
      expect(decider.decide(g, hero).amount, rawTo);
    });

    test('damps further as ladder pressure and bubble factor rise', () {
      final (g, hero) = deepStack();
      final rawTo = g.minRaiseTo(hero) + 600;
      final level1 = dampedRaiseTo(g, hero, rawTo).amount;
      final nearBubble = dampedRaiseTo(g, hero, rawTo,
              ladderPressure: 0.6, bubbleFactor: 1.5)
          .amount;
      expect(nearBubble, lessThan(level1));
    });

    test('never shrinks a raise below the legal minimum', () {
      final (g, hero) = deepStack();
      final rawTo = g.minRaiseTo(hero) + 10; // barely above minimum already
      final damped = dampedRaiseTo(g, hero, rawTo,
          ladderPressure: 0.6, bubbleFactor: 1.5);
      expect(damped.amount, greaterThanOrEqualTo(g.minRaiseTo(hero)));
    });

    test('never resizes an all-in', () {
      final (g, hero) = deepStack();
      final decider = IcmAdjustedDecider(
        const _Fixed(GameAction.allIn()),
        (game, p) => _ctx(stackBb: 100, bubble: 1.5),
      );
      expect(decider.decide(g, hero).type, ActionType.allIn);
    });
  });

  group('IcmAdjustedDecider icmDiscipline flag and the garbage-call trim', () {
    (PokerGame, Player) facingRaise({required List<Card> hero}) {
      final players = [
        Player(id: 'h', name: 'H', stack: 20000),
        Player(id: 'v', name: 'V', stack: 20000),
      ];
      final g = PokerGame(
        players: players,
        smallBlind: 100,
        bigBlind: 200,
        deck: Deck(random: Random(4)),
      )
        ..buttonIndex = 1
        ..startHand();
      g.applyAction(GameAction.raise(600));
      final h = g.currentPlayer!; // p0 (BB) facing the open
      h.hole
        ..clear()
        ..addAll(hero);
      return (g, h);
    }

    // A large-relative-stack all-in call, the shape `_bubbleTighten` actually
    // gates on (commitFrac >= 0.4) — `facingRaise` above deliberately commits
    // a tiny fraction of a deep stack so it isolates the garbage-call trim
    // from this logic; these two tests need the opposite shape.
    (PokerGame, Player) facingShove(List<Card> hero) {
      final players = [
        Player(id: 'p0', name: 'P0', stack: 1000),
        Player(id: 'p1', name: 'P1', stack: 1000),
      ];
      final g = PokerGame(
        players: players,
        smallBlind: 10,
        bigBlind: 20,
        deck: Deck(random: Random(2)),
      )
        ..buttonIndex = 1
        ..startHand();
      g.applyAction(GameAction.raise(g.maxRaiseTo(g.currentPlayer!)));
      final h = g.currentPlayer!; // p0 (BB), ~50bb, facing an all-in
      h.hole
        ..clear()
        ..addAll(hero);
      return (g, h);
    }

    test('with icmDiscipline off, ICM-math folding does not fire', () {
      // A marginal call that _bubbleTighten would demote near the bubble.
      final (g, hero) = facingShove(cards('Kd Ts'));
      final decider = IcmAdjustedDecider(
        const _Fixed(GameAction.call()),
        (game, p) => _ctx(stackBb: 50, bubble: 1.8),
        icmDiscipline: false,
      );
      expect(decider.decide(g, hero).type, ActionType.call,
          reason: 'bubble folding discipline is a skill amateurs do not get');
    });

    test('with icmDiscipline on, the same spot still folds', () {
      final (g, hero) = facingShove(cards('Kd Ts'));
      final decider = IcmAdjustedDecider(
        const _Fixed(GameAction.call()),
        (game, p) => _ctx(stackBb: 50, bubble: 1.8),
        icmDiscipline: true,
      );
      expect(decider.decide(g, hero).type, ActionType.fold);
    });

    test('the garbage-call trim fires regardless of icmDiscipline', () {
      // 7-2 offsuit calling an open is well below the weak bar in any context.
      var folds = 0;
      const trials = 200;
      for (var seed = 0; seed < trials; seed++) {
        final (g, hero) = facingRaise(hero: cards('7c 2d'));
        final decider = IcmAdjustedDecider(
          const _Fixed(GameAction.call()),
          (game, p) => _ctx(stackBb: 100),
          icmDiscipline: false,
          random: Random(seed),
        );
        if (decider.decide(g, hero).type == ActionType.fold) folds++;
      }
      expect(folds, greaterThan(0),
          reason: 'some garbage calls should be trimmed even without '
              'icmDiscipline');
      expect(folds, lessThan(trials),
          reason: 'a chance, not a hard cutoff — some garbage calls survive');
    });

    test('the trim never touches a defensible marginal call', () {
      // A real hand a station/chaser would call with — must never be trimmed,
      // however high the pressure. Otherwise this is a nit-fest, not a fix.
      var folds = 0;
      const trials = 200;
      for (var seed = 0; seed < trials; seed++) {
        final (g, hero) = facingRaise(hero: cards('Ac Qc'));
        final decider = IcmAdjustedDecider(
          const _Fixed(GameAction.call()),
          (game, p) => _ctx(stackBb: 100, bubble: 1.8),
          icmDiscipline: false,
          random: Random(seed),
        );
        if (decider.decide(g, hero).type == ActionType.fold) folds++;
      }
      expect(folds, 0);
    });

    test('never trims a free check', () {
      final (g, hero) = _short(cards('7c 2d'), stackBb: 100);
      final decider = IcmAdjustedDecider(
        const _Fixed(GameAction.check()),
        (game, p) => _ctx(stackBb: 100),
        icmDiscipline: false,
      );
      expect(decider.decide(g, hero).type, ActionType.check);
    });
  });
}
