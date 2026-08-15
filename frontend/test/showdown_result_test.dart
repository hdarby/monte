import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

import '_helpers.dart';

HandResult _resultFor(PokerGame game, String id) =>
    game.results.firstWhere((r) => r.player.id == id);

void main() {
  group('showdown results: chops and uncalled bets', () {
    test('a tie splits the pot — both results are chops', () {
      // Both players play the board (broadway straight A-K-Q-J-T) — a chop.
      // Deal order: holes round-robin (p0,p1,p0,p1), then burn+flop, burn+turn,
      // burn+river.
      final deck = Deck.stacked(
        cards('2c 4h 3d 5s 6c As Kd Qh 8c Jc 9c Ts'),
      );
      final players = [
        Player(id: 'p0', name: 'P0', stack: 100),
        Player(id: 'p1', name: 'P1', stack: 100),
      ];
      final game = PokerGame(
        players: players,
        smallBlind: 1,
        bigBlind: 2,
        deck: deck,
        rotateButton: false,
      )..startHand();

      // Check/call the hand down to showdown.
      while (!game.isHandOver) {
        final p = game.currentPlayer;
        if (p == null) break;
        game.applyAction(
          game.canCheck(p) ? const GameAction.check() : const GameAction.call(),
        );
      }

      final p0 = _resultFor(game, 'p0');
      final p1 = _resultFor(game, 'p1');
      expect(p0.isSplit, isTrue, reason: 'a tie is a chop');
      expect(p1.isSplit, isTrue);
      expect(p0.netWon, 2, reason: 'each takes half of the 4-chip pot');
      expect(p1.netWon, 2);
      // Chips conserved.
      expect(players[0].stack + players[1].stack, 200);
    });

    test('an uncalled over-bet is returned, not shown as won', () {
      // P0 (button/SB, 300) shoves; P1 (BB, 100) calls all-in and wins with AA.
      // P0's 200 excess is uncalled — returned, not won.
      final deck = Deck.stacked(
        cards('2c As 3d Ad 6c Kh Qs 7d 8c 4h 9c 5s'),
      );
      final players = [
        Player(id: 'p0', name: 'P0', stack: 300),
        Player(id: 'p1', name: 'P1', stack: 100),
      ];
      final game = PokerGame(
        players: players,
        smallBlind: 1,
        bigBlind: 2,
        deck: deck,
        rotateButton: false,
      )..startHand();

      final shover = game.currentPlayer!; // P0 (SB acts first heads-up)
      expect(shover.id, 'p0');
      game.applyAction(GameAction.raise(game.maxRaiseTo(shover)));
      game.applyAction(const GameAction.call()); // P1 calls all-in
      expect(game.isHandOver, isTrue);

      final p1 = _resultFor(game, 'p1'); // the winner
      final p0 = _resultFor(game, 'p0'); // the over-bettor
      expect(p1.netWon, 200, reason: 'P1 wins the 200 contested pot');
      expect(p1.isSplit, isFalse);

      expect(p0.uncalledReturn, 200, reason: "P0's over-bet comes back");
      expect(p0.netWon, 0,
          reason: 'P0 won nothing from anyone — just got its own money back');

      // Chips conserved: 400 in, 400 out.
      expect(players[0].stack + players[1].stack, 400);
    });

    test('netGain is the change in the stack, not the pot collected', () {
      // Same spot as above: P1 (100) wins a 200 pot after putting 100 of their
      // own into it, so they *made* 100 — half what the pot figure suggests.
      final deck = Deck.stacked(
        cards('2c As 3d Ad 6c Kh Qs 7d 8c 4h 9c 5s'),
      );
      final players = [
        Player(id: 'p0', name: 'P0', stack: 300),
        Player(id: 'p1', name: 'P1', stack: 100),
      ];
      final game = PokerGame(
        players: players,
        smallBlind: 1,
        bigBlind: 2,
        deck: deck,
        rotateButton: false,
      )..startHand();
      game.applyAction(GameAction.raise(game.maxRaiseTo(game.currentPlayer!)));
      game.applyAction(const GameAction.call());

      final p1 = _resultFor(game, 'p1');
      final p0 = _resultFor(game, 'p0');
      expect(p1.amountWon, 200, reason: 'the pot they scooped');
      expect(p1.netGain, 100, reason: 'but half of it was their own money');
      expect(p1.netGain, players[1].stack - 100,
          reason: 'net gain must equal the change in the stack');

      // The loser is down exactly what they put in.
      expect(p0.netGain, -100);
      expect(p0.netGain, players[0].stack - 300);
    });

    test('a chop can be a net loss, which the pot figure cannot show', () {
      // Both play the board and split, each getting back less than they put in
      // is impossible heads-up — but each *gains* nothing, and the pot figure
      // would still read as a win.
      final deck = Deck.stacked(
        cards('2c 4h 3d 5s 6c As Kd Qh 8c Jc 9c Ts'),
      );
      final players = [
        Player(id: 'p0', name: 'P0', stack: 100),
        Player(id: 'p1', name: 'P1', stack: 100),
      ];
      final game = PokerGame(
        players: players,
        smallBlind: 1,
        bigBlind: 2,
        deck: deck,
        rotateButton: false,
      )..startHand();
      while (!game.isHandOver) {
        final p = game.currentPlayer;
        if (p == null) break;
        game.applyAction(
          game.canCheck(p) ? const GameAction.check() : const GameAction.call(),
        );
      }

      for (final id in ['p0', 'p1']) {
        final r = _resultFor(game, id);
        expect(r.amountWon, greaterThan(0), reason: '$id collected chips');
        expect(r.netGain, 0,
            reason: '$id got exactly its own money back — a gain of nothing');
      }
      expect(players[0].stack, 100);
      expect(players[1].stack, 100);
    });
  });
}
