import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

import '_helpers.dart';

/// Drives a game to terminal with a passive policy (check when possible,
/// otherwise call). Deterministic given the deck, so two identical states play
/// out identically.
void _playPassively(PokerGame g) {
  var guard = 0;
  while (g.currentPlayer != null) {
    final p = g.currentPlayer!;
    g.applyAction(
      g.canCheck(p) ? const GameAction.check() : const GameAction.call(),
    );
    if (++guard > 1000) fail('Passive play did not terminate');
  }
}

List<Player> _table() => [
  Player(id: 'p0', name: 'P0', stack: 1000, isHuman: true),
  Player(id: 'p1', name: 'P1', stack: 1000),
  Player(id: 'p2', name: 'P2', stack: 1000),
];

void main() {
  group('Deck', () {
    test('stacked deals in the given order, front-to-back', () {
      final order = cards('As Kd Qh Jc Ts');
      final deck = Deck.stacked(order);
      expect(deck.remaining, 5);
      final dealt = [for (var i = 0; i < 5; i++) deck.deal()];
      expect(dealt, order);
      expect(deck.remaining, 0);
    });

    test('copy preserves remaining order and is independent', () {
      final deck = Deck.stacked(cards('As Kd Qh Jc Ts'));
      deck.deal(); // remove As; remaining: Kd Qh Jc Ts
      final copy = deck.copy();

      expect(copy.remaining, deck.remaining);
      // Dealing from the copy does not touch the original.
      expect(copy.deal(), card('Kd'));
      expect(deck.remaining, 4);
      // Both decks deal the same next card from the same position.
      expect(deck.deal(), card('Kd'));
    });

    test('loadRemaining replaces the future with a known order', () {
      final deck = Deck.stacked(cards('As Kd'));
      deck.loadRemaining(cards('2c 3d 4h'));
      expect(deck.remaining, 3);
      expect([deck.deal(), deck.deal(), deck.deal()], cards('2c 3d 4h'));
    });
  });

  group('Player.clone', () {
    test('is an independent deep copy', () {
      final p = Player(id: 'p', name: 'P', stack: 500)
        ..currentBet = 20
        ..totalContributed = 60
        ..hasActedThisRound = true;
      p.hole.addAll(cards('As Ah'));

      final c = p.clone();
      expect(c.stack, 500);
      expect(c.currentBet, 20);
      expect(c.totalContributed, 60);
      expect(c.hasActedThisRound, isTrue);
      expect(c.hole, cards('As Ah'));

      // Mutating the clone leaves the original untouched.
      c
        ..stack = 0
        ..hasFolded = true;
      c.hole.clear();
      expect(p.stack, 500);
      expect(p.hasFolded, isFalse);
      expect(p.hole, cards('As Ah'));
    });
  });

  group('PokerGame.clone', () {
    test('clone played forward matches the original played forward', () {
      final original = PokerGame(
        players: _table(),
        deck: Deck(random: Random(7)),
      )..startHand();
      final clone = original.clone();

      _playPassively(original);
      _playPassively(clone);

      expect(clone.board, original.board);
      expect(clone.pot, original.pot);
      expect(
        [for (final p in clone.players) p.stack],
        [for (final p in original.players) p.stack],
      );
      expect(
        [for (final r in clone.results) r.amountWon],
        [for (final r in original.results) r.amountWon],
      );
    });

    test('playing the clone does not mutate the original', () {
      final original = PokerGame(
        players: _table(),
        deck: Deck(random: Random(9)),
      )..startHand();
      final stacksAtClone = [for (final p in original.players) p.stack];
      final clone = original.clone();

      _playPassively(clone);

      // Clone reached the end; original is untouched at the post-deal position.
      expect(clone.isHandOver, isTrue);
      expect(original.isHandOver, isFalse);
      expect(original.round, BettingRound.preflop);
      expect(original.board, isEmpty);
      expect([for (final p in original.players) p.stack], stacksAtClone);
    });
  });
}
