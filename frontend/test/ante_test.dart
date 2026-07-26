import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

import '_helpers.dart';

// A 52-card order (round-robin deal for 2 players, then burn/flop/burn/turn/
// burn/river) placing the given holes + board; the rest fills the gaps.
List<Card> _order({
  required List<Card> p0,
  required List<Card> p1,
  required List<Card> board, // flop(3) + turn + river = 5
}) {
  final placed = <int, Card>{
    0: p0[0], 2: p0[1],
    1: p1[0], 3: p1[1],
    5: board[0], 6: board[1], 7: board[2], // flop (4 = burn)
    9: board[3], // turn (8 = burn)
    11: board[4], // river (10 = burn)
  };
  final used = placed.values.toSet();
  final rest = [
    for (final s in Suit.values)
      for (final r in Rank.values)
        if (!used.contains(Card(r, s))) Card(r, s),
  ];
  var i = 0;
  return [for (var k = 0; k < 52; k++) placed[k] ?? rest[i++]];
}

PokerGame _hu(int ante, {Deck? deck, int p0 = 1000, int p1 = 1000}) => PokerGame(
      players: [
        Player(id: 'p0', name: 'P0', stack: p0),
        Player(id: 'p1', name: 'P1', stack: p1),
      ],
      smallBlind: 10,
      bigBlind: 20,
      ante: ante,
      deck: deck,
    );

void main() {
  group('big-blind ante', () {
    test('ante==0 leaves the pot as just the blinds', () {
      final g = _hu(0)..startHand();
      expect(g.pot, 30); // sb 10 + bb 20
    });

    test('the big blind posts the ante and it sits in the pot', () {
      final g = _hu(20)..startHand();
      // Heads-up: seat 1 is the big blind. It's down bb + ante.
      expect(g.players[1].stack, 1000 - 20 - 20);
      expect(g.pot, 10 + 20 + 20); // sb + bb + ante
    });

    test('a short big blind goes all-in on the ante for what it can', () {
      final g = _hu(20, p1: 25)..startHand(); // BB has 25: posts 20 blind, 5 ante
      expect(g.players[1].isAllIn, isTrue);
      expect(g.players[1].stack, 0);
      expect(g.pot, 10 + 20 + 5); // sb + bb + partial ante
    });

    test('the ante is won by the best hand, not returned to the big blind', () {
      // p0 makes quad aces; both check/call to showdown. If the ante were mis-
      // handled as a solo layer it would come back to the BB (p1) instead.
      final deck = Deck.stacked(_order(
        p0: cards('As Ac'),
        p1: cards('2h 3d'),
        board: cards('Ah Ad Kc 5s 7d'),
      ));
      final g = _hu(20, deck: deck)..startHand();
      while (!g.isHandOver) {
        final p = g.currentPlayer!;
        g.applyAction(g.canCheck(p) ? const GameAction.check() : const GameAction.call());
      }
      // Pot was 20 + 20 + 20 ante = 60, all to p0.
      expect(g.players[0].stack, 1000 - 20 + 60); // 1040
      expect(g.players[1].stack, 1000 - 20 - 20); // 960 (lost blind + ante)
      expect(g.players[0].stack + g.players[1].stack, 2000); // chips conserved
    });

    test('clone() round-trips the ante and posted dead money', () {
      final g = _hu(20)..startHand();
      final c = g.clone();
      expect(c.ante, 20);
      expect(c.pot, g.pot); // dead money copied
    });
  });
}
