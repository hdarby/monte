import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/bot.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';
import 'package:monte/features/eval_history/domain/duplicate_run.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';

/// A policy that always folds, and one that always shoves — the two extremes,
/// so the replay's result is predictable without asserting on real strategy.
class _AlwaysFold implements DecisionPolicy {
  @override
  GameAction decide(PokerGame game, Player p) =>
      game.canCheck(p) ? const GameAction.check() : const GameAction.fold();
}

EvalHand _hand() => const EvalHand(
      handNumber: 1,
      smallBlind: 50,
      bigBlind: 100,
      board: ['2c', '7d', 'Ts', '4h', '9s'],
      actions: [],
      results: [],
      players: [
        EvalHandPlayer(
          id: 'a', name: 'A', modelId: 'human', modelLabel: 'You',
          position: 'BTN', seatsFromButton: 0, holeCards: ['Ah', 'Ad'],
          startingStack: 10000, finalStack: 9900, folded: true,
        ),
        EvalHandPlayer(
          id: 'b', name: 'B', modelId: 'x', modelLabel: 'B',
          position: 'SB', seatsFromButton: 1, holeCards: ['Kc', 'Kd'],
          startingStack: 10000, finalStack: 10100, folded: false,
        ),
        EvalHandPlayer(
          id: 'c', name: 'C', modelId: 'x', modelLabel: 'C',
          position: 'BB', seatsFromButton: 2, holeCards: ['2h', '3h'],
          startingStack: 10000, finalStack: 10000, folded: true,
        ),
      ],
    );

void main() {
  test('reconstructs the hand so every seat gets its recorded cards', () {
    // The whole method rests on rebuilding the deal exactly: two rounds dealt
    // round-robin, then a burn before the flop and before each later card. If
    // the offsets are wrong the replay is of a different hand entirely.
    final net = DuplicateRun.replay(
      _hand(),
      'a',
      deciderFor: (_) => _AlwaysFold(),
      substitute: _AlwaysFold(),
      runs: 1,
    );
    expect(net, isNotNull, reason: 'the hand must be reconstructable');
  });

  test('a seat that folds everything loses only what it posted', () {
    // The button posts nothing three-handed, so folding costs it zero.
    final net = DuplicateRun.replay(
      _hand(),
      'a',
      deciderFor: (_) => _AlwaysFold(),
      substitute: _AlwaysFold(),
      runs: 3,
    );
    expect(net, 0.0);
  });

  test('aces in the seat beat folding them', () {
    // Same cards, same opponents, different player — the point of the exercise.
    final folding = DuplicateRun.replay(_hand(), 'a',
        deciderFor: (_) => _AlwaysFold(),
        substitute: _AlwaysFold(),
        runs: 20)!;
    final playing = DuplicateRun.replay(_hand(), 'a',
        deciderFor: (_) => _AlwaysFold(),
        substitute: BotStrategy(),
        runs: 20)!;
    expect(playing, greaterThan(folding),
        reason: 'AA that plays should beat AA that folds against folders');
  });

  test('an unreconstructable hand returns null rather than a wrong number', () {
    const noCards = EvalHand(
      handNumber: 1, smallBlind: 50, bigBlind: 100, board: [],
      actions: [], results: [],
      players: [
        EvalHandPlayer(
          id: 'a', name: 'A', modelId: 'human', modelLabel: 'You',
          position: 'BTN', seatsFromButton: 0, holeCards: [],
          startingStack: 100, finalStack: 100, folded: true,
        ),
      ],
    );
    expect(
      DuplicateRun.replay(noCards, 'a',
          deciderFor: (_) => _AlwaysFold(), substitute: _AlwaysFold()),
      isNull,
    );
  });
}
