import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/ismcts.dart';
import 'package:monte/core/domain/engine/bot.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

const _startingStack = 1000;
const _bigBlind = 10;

/// Plays one heads-up hand with the MCTS bot in [mctsSeat] (the other seat is
/// the heuristic bot) and returns the MCTS player's net chips for the hand.
/// The deck is seeded by [deckSeed] so the same deal can be replayed with the
/// seats swapped (duplicate matching), cancelling card luck.
int _playHand({
  required int mctsSeat,
  required int deckSeed,
  required int iterations,
}) {
  final players = [
    Player(id: 'p0', name: 'P0', stack: _startingStack),
    Player(id: 'p1', name: 'P1', stack: _startingStack),
  ];
  final game = PokerGame(
    players: players,
    deck: Deck(random: Random(deckSeed)),
  );
  final mcts = IsmctsEngine(
    config: IsmctsConfig(iterations: iterations),
    random: Random(7000 + deckSeed),
  );
  final heuristic = BotStrategy(random: Random(9000 + deckSeed));

  game.startHand();
  var guard = 0;
  while (!game.isHandOver) {
    final current = game.currentPlayer;
    if (current == null) break;
    final isMcts = players.indexOf(current) == mctsSeat;
    game.applyAction(
      isMcts
          ? mcts.chooseAction(game, current)
          : heuristic.decide(game, current),
    );
    if (++guard > 500) fail('hand did not terminate');
  }
  return players[mctsSeat].stack - _startingStack;
}

void main() {
  test('MCTS bot beats the heuristic bot heads-up (duplicate match)', () {
    const deals = 40; // each played twice (seats swapped) = 80 hands
    const iterations = 250;

    var net = 0;
    for (var d = 0; d < deals; d++) {
      net += _playHand(mctsSeat: 0, deckSeed: d, iterations: iterations);
      net += _playHand(mctsSeat: 1, deckSeed: d, iterations: iterations);
    }

    final hands = deals * 2;
    final bbPer100 = net / _bigBlind / hands * 100;
    // ignore: avoid_print
    print(
      'MCTS vs heuristic: net=$net over $hands hands = '
      '${bbPer100.toStringAsFixed(1)} bb/100',
    );

    // The run is fully seeded, so this is deterministic (observed ~43 bb/100).
    // The threshold leaves generous headroom while still asserting a decisive,
    // not marginal, edge over the heuristic.
    expect(
      bbPer100,
      greaterThan(15),
      reason: 'MCTS should beat the heuristic by a real margin',
    );
  });
}
