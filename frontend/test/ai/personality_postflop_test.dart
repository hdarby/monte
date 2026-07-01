import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/ai/personality_policy.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

import '../_helpers.dart';

// Heads-up deal order placing both holes and the flop where the engine deals
// them (p0,p1,p0,p1; burn; flop×3; ...). Turn/river are filled arbitrarily.
List<Card> _stack({
  required List<Card> p0,
  required List<Card> p1,
  required List<Card> flop,
}) {
  final placed = <int, Card>{
    0: p0[0], 2: p0[1],
    1: p1[0], 3: p1[1],
    5: flop[0], 6: flop[1], 7: flop[2],
  };
  final used = placed.values.toSet();
  final rest = [
    for (final suit in Suit.values)
      for (final rank in Rank.values)
        if (!used.contains(Card(rank, suit))) Card(rank, suit),
  ];
  var r = 0;
  return [for (var i = 0; i < 52; i++) placed[i] ?? rest[r++]];
}

PokerGame _game(List<Card> order) => PokerGame(
      players: [
        Player(id: 'p0', name: 'P0', stack: 1000, isHuman: true),
        Player(id: 'p1', name: 'P1', stack: 1000),
      ],
      deck: Deck.stacked(order),
    )..startHand();

// Play preflop passively (call/check) until the flop is out.
void _toFlop(PokerGame g) {
  while (g.round == BettingRound.preflop) {
    final p = g.currentPlayer!;
    g.applyAction(g.canCheck(p) ? const GameAction.check() : const GameAction.call());
  }
}

Player _p(PokerGame g, String id) => g.players.firstWhere((x) => x.id == id);

// Fraction of decisions that bet/raise (aggressive) over [trials] samples.
double _aggressiveRate(PersonalityPolicy pol, PokerGame g, Player hero, int trials) {
  var n = 0;
  for (var i = 0; i < trials; i++) {
    final t = pol.decide(g, hero).type;
    if (t == ActionType.bet || t == ActionType.raise) n++;
  }
  return n / trials;
}

// Fraction of decisions that continue (call/bet/raise, i.e. not fold).
double _continueRate(PersonalityPolicy pol, PokerGame g, Player hero, int trials) {
  var n = 0;
  for (var i = 0; i < trials; i++) {
    if (pol.decide(g, hero).type != ActionType.fold) n++;
  }
  return n / trials;
}

PersonalityPolicy _pol(PersonalityProfile profile) =>
    PersonalityPolicy(profile, random: Random(7), rangeAware: true);

void main() {
  const trials = 200;

  group('range-aware personality postflop', () {
    test('maniac bluffs air far more than a nit (no bet to face)', () {
      // Hero (p1) acts first on the flop with 7-2 offsuit air on a dry K-high
      // board; there is no bet to face.
      final g = _game(_stack(
        p0: cards('Ah Ad'),
        p1: cards('7c 2d'),
        flop: cards('Kh 8s 3c'),
      ));
      _toFlop(g);
      final hero = _p(g, 'p1');
      expect(g.currentPlayer!.id, 'p1');
      expect(g.callAmount(hero), 0);

      final maniac = _aggressiveRate(_pol(const PersonalityProfile.maniac()), g, hero, trials);
      final nit = _aggressiveRate(_pol(const PersonalityProfile.nit()), g, hero, trials);
      expect(maniac, greaterThan(nit + 0.2));
    });

    test('station continues a marginal hand where a nit overfolds', () {
      // Hero (p1) holds an underpair (77) on a K-high board and faces a pot bet.
      final g = _game(_stack(
        p0: cards('Ah Qd'),
        p1: cards('7c 7d'),
        flop: cards('Kh 8s 3c'),
      ));
      _toFlop(g);
      // p1 checks, p0 bets pot, so p1 now faces a bet.
      g.applyAction(const GameAction.check());
      final pot = g.pot;
      final villain = g.currentPlayer!; // p0
      g.applyAction(GameAction.bet(villain.currentBet + pot));
      final hero = _p(g, 'p1');
      expect(g.currentPlayer!.id, 'p1');
      expect(g.callAmount(hero), greaterThan(0));

      final station = _continueRate(_pol(const PersonalityProfile.station()), g, hero, trials);
      final nit = _continueRate(_pol(const PersonalityProfile.nit()), g, hero, trials);
      expect(station, greaterThan(nit));
    });

    test('a stronger hand is bet/raised more than a weak one', () {
      // Same dry board, no bet to face; a set (88) should act aggressively far
      // more than 7-2 air for the same balanced profile.
      PokerGame heroWith(List<Card> holes) {
        final g = _game(_stack(
          p0: cards('Ah Ad'),
          p1: holes,
          flop: cards('Kh 8s 3c'),
        ));
        _toFlop(g);
        return g;
      }

      final strong = heroWith(cards('8c 8d'));
      final weak = heroWith(cards('7c 2d'));
      final profile = const PersonalityProfile.tag();
      final strongRate =
          _aggressiveRate(_pol(profile), strong, _p(strong, 'p1'), trials);
      final weakRate =
          _aggressiveRate(_pol(profile), weak, _p(weak, 'p1'), trials);
      expect(strongRate, greaterThan(weakRate));
    });
  });
}
