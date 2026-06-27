import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/action_abstraction.dart';
import 'package:monte/core/domain/ai/ismcts.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/ai/personality_policy.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

/// Measures a policy's behavior at a standard spot: heads-up, the SB opens to
/// 30, and the big blind must decide. Returns the fraction of hands the BB
/// plays (VPIP — any non-fold) and the fraction it bets/raises (aggression).
({double vpip, double aggressive}) _measure(
  PersonalityProfile profile, {
  int trials = 400,
}) {
  final policy = PersonalityPolicy(profile, random: Random(1));
  var voluntary = 0;
  var aggressive = 0;
  for (var i = 0; i < trials; i++) {
    final players = [
      Player(id: 'p0', name: 'P0', stack: 1000),
      Player(id: 'p1', name: 'P1', stack: 1000),
    ];
    final game = PokerGame(
      players: players,
      deck: Deck(random: Random(i)),
    )..startHand();
    game.applyAction(const GameAction.raise(30)); // SB opens
    final action = policy.decide(game, game.currentPlayer!); // BB decides
    if (action.type != ActionType.fold) voluntary++;
    if (action.type == ActionType.bet || action.type == ActionType.raise) {
      aggressive++;
    }
  }
  return (vpip: voluntary / trials, aggressive: aggressive / trials);
}

void main() {
  group('PersonalityPolicy axis monotonicity', () {
    test('higher tightness lowers VPIP', () {
      double vpip(double t) => _measure(
        PersonalityProfile(tightness: t, aggression: 0.4, bluffFrequency: 0),
      ).vpip;

      expect(vpip(0.1), greaterThan(vpip(0.5)));
      expect(vpip(0.5), greaterThan(vpip(0.9)));
    });

    test('higher aggression raises the bet/raise frequency', () {
      double aggr(double a) => _measure(
        PersonalityProfile(aggression: a, tightness: 0.4, bluffFrequency: 0),
      ).aggressive;

      expect(aggr(0.1), lessThan(aggr(0.5)));
      expect(aggr(0.5), lessThan(aggr(0.9)));
    });

    test('higher bluff frequency raises the bet/raise frequency', () {
      double aggr(double b) => _measure(
        PersonalityProfile(bluffFrequency: b, aggression: 0.4, tightness: 0.5),
      ).aggressive;

      expect(aggr(0.0), lessThan(aggr(0.5)));
      expect(aggr(0.5), lessThan(aggr(1.0)));
    });

    test('higher risk tolerance widens calling (more VPIP)', () {
      double vpip(double r) => _measure(
        PersonalityProfile(
          riskTolerance: r,
          tightness: 0.6,
          aggression: 0.3,
          bluffFrequency: 0,
        ),
      ).vpip;

      expect(vpip(0.1), lessThan(vpip(0.9)));
    });
  });

  test('an MCTS engine accepts a personality and returns a legal action', () {
    final players = [
      Player(id: 'p0', name: 'P0', stack: 1000),
      Player(id: 'p1', name: 'P1', stack: 1000),
    ];
    final game = PokerGame(
      players: players,
      deck: Deck(random: Random(3)),
    )..startHand();
    while (game.round == BettingRound.preflop) {
      final p = game.currentPlayer!;
      game.applyAction(
        game.canCheck(p) ? const GameAction.check() : const GameAction.call(),
      );
    }
    final hero = game.currentPlayer!;

    const maniac = PersonalityProfile.maniac();
    final action = IsmctsEngine(
      config: const IsmctsConfig(iterations: 200),
      random: Random(5),
      profile: maniac,
      rolloutPolicy: PersonalityPolicy(maniac, random: Random(6)),
    ).chooseAction(game, hero);

    final legal = const ActionAbstraction().actionsFor(game, hero);
    expect(
      legal.any((a) => a.type == action.type && a.amount == action.amount),
      isTrue,
    );
  });
}
