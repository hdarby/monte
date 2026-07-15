import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

void main() {
  group('Player.betLevel (bet escalation for the UI)', () {
    test('preflop open / 3-bet / 4-bet get levels 1 / 2 / 3', () {
      final players = [
        Player(id: 'p0', name: 'P0', stack: 1000),
        Player(id: 'p1', name: 'P1', stack: 1000),
        Player(id: 'p2', name: 'P2', stack: 1000),
      ];
      final game = PokerGame(
        players: players,
        smallBlind: 5,
        bigBlind: 10,
        deck: Deck(random: Random(1)),
      )..startHand();

      final opener = game.currentPlayer!;
      game.applyAction(GameAction.raise(game.minRaiseTo(opener)));
      expect(opener.betLevel, 1, reason: 'the open is level 1 (plain bet)');
      expect(opener.wagerIsCall, isFalse, reason: 'a raise is not a call');

      final threeBettor = game.currentPlayer!;
      game.applyAction(GameAction.raise(game.minRaiseTo(threeBettor)));
      expect(threeBettor.betLevel, 2, reason: 'a 3-bet is level 2 (orange)');

      final fourBettor = game.currentPlayer!;
      game.applyAction(GameAction.raise(game.minRaiseTo(fourBettor)));
      expect(fourBettor.betLevel, 3, reason: 'a 4-bet is level 3 (red)');

      // A call takes on the level it called, so its indicator matches the raise.
      final caller = game.currentPlayer!;
      game.applyAction(const GameAction.call());
      expect(caller.betLevel, 3, reason: 'calling the 4-bet matches level 3');
      expect(caller.wagerIsCall, isTrue, reason: 'this wager was a call');
    });

    test('a limp (calling an unraised pot) stays at level 0', () {
      final players = [
        Player(id: 'p0', name: 'P0', stack: 1000),
        Player(id: 'p1', name: 'P1', stack: 1000),
        Player(id: 'p2', name: 'P2', stack: 1000),
      ];
      final game = PokerGame(
        players: players,
        smallBlind: 5,
        bigBlind: 10,
        deck: Deck(random: Random(2)),
      )..startHand();

      // First to act calls the big blind with no prior raise — a limp.
      final limper = game.currentPlayer!;
      game.applyAction(const GameAction.call());
      expect(limper.betLevel, 0, reason: 'a limp is neutral (like a blind)');
    });

    test('reset clears the level for a new round/hand', () {
      final p = Player(id: 'x', name: 'x', stack: 100)..betLevel = 3;
      p.resetForRound();
      expect(p.betLevel, 0);

      p.betLevel = 2;
      p.resetForHand();
      expect(p.betLevel, 0);
    });
  });
}
