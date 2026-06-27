import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/bot.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

void main() {
  group('PokerGame invariants', () {
    test('chips are conserved across many randomized hands', () {
      const startingStack = 1000;
      final players = [
        Player(id: 'p0', name: 'P0', stack: startingStack, isHuman: true),
        Player(id: 'p1', name: 'P1', stack: startingStack),
        Player(id: 'p2', name: 'P2', stack: startingStack),
        Player(id: 'p3', name: 'P3', stack: startingStack),
      ];
      final total = players.fold<int>(0, (s, p) => s + p.stack);

      final bot = BotStrategy(random: Random(42));
      final game = PokerGame(
        players: players,
        deck: Deck(random: Random(7)),
      );

      var handsPlayed = 0;
      for (var h = 0; h < 200; h++) {
        if (players.where((p) => p.stack > 0).length < 2) break;
        game.startHand();
        if (game.isHandOver) break;

        var guard = 0;
        while (!game.isHandOver) {
          final current = game.currentPlayer;
          if (current == null) break;
          game.applyAction(bot.decide(game, current));
          if (++guard > 500) fail('Hand did not terminate');
        }
        handsPlayed++;

        // No negative stacks, and the bank is exactly conserved.
        for (final p in players) {
          expect(
            p.stack,
            greaterThanOrEqualTo(0),
            reason: '${p.name} went negative',
          );
        }
        final now = players.fold<int>(0, (s, p) => s + p.stack);
        expect(now, total, reason: 'chip leak after hand $h');
      }

      expect(handsPlayed, greaterThan(5));
    });

    test('button rotates between hands', () {
      final players = [
        Player(id: 'p0', name: 'P0', stack: 1000),
        Player(id: 'p1', name: 'P1', stack: 1000),
        Player(id: 'p2', name: 'P2', stack: 1000),
      ];
      final game = PokerGame(
        players: players,
        deck: Deck(random: Random(1)),
      );
      final bot = BotStrategy(random: Random(1));

      final buttons = <int>[];
      for (var h = 0; h < 3; h++) {
        buttons.add(game.buttonIndex);
        game.startHand();
        while (!game.isHandOver) {
          final c = game.currentPlayer;
          if (c == null) break;
          game.applyAction(bot.decide(game, c));
        }
      }
      expect(buttons.toSet().length, greaterThan(1));
    });
  });
}
