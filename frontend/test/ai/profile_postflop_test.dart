import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/core/domain/ai/profile_postflop_policy.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

import '../_helpers.dart';

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

void _toFlop(PokerGame g) {
  while (g.round == BettingRound.preflop) {
    final p = g.currentPlayer!;
    g.applyAction(g.canCheck(p) ? const GameAction.check() : const GameAction.call());
  }
}

Player _p(PokerGame g, String id) => g.players.firstWhere((x) => x.id == id);

ProfilePostflopPolicy _pol(PlayerProfile profile) =>
    ProfilePostflopPolicy(profile, random: Random(11));

double _aggressiveRate(ProfilePostflopPolicy pol, PokerGame g, Player hero, int n) {
  var a = 0;
  for (var i = 0; i < n; i++) {
    final t = pol.decide(g, hero).type;
    if (t == ActionType.bet || t == ActionType.raise) a++;
  }
  return a / n;
}

// Advance to flop; hero (p1) checks, villain (p0) bets [potFraction] of the pot,
// leaving hero to act facing that bet.
PokerGame _facingBet({
  required List<Card> p0,
  required List<Card> p1,
  required List<Card> flop,
  required double potFraction,
}) {
  final g = _game(_stack(p0: p0, p1: p1, flop: flop));
  _toFlop(g);
  g.applyAction(const GameAction.check()); // p1
  final villain = g.currentPlayer!; // p0
  g.applyAction(GameAction.bet(villain.currentBet + (g.pot * potFraction).round()));
  return g;
}

void main() {
  const trials = 200;

  group('ProfilePostflopPolicy (GTO vs exploitative)', () {
    test('the GTO anchor continues a strong hand and folds trash on pot odds', () {
      // Set of eights on K83 rainbow facing a half-pot bet -> way ahead.
      final strong = _facingBet(
        p0: cards('Ah Qd'),
        p1: cards('8c 8d'),
        flop: cards('Kh 8s 3c'),
        potFraction: 0.5,
      );
      expect(
        _pol(isaacHaxton).decide(strong, _p(strong, 'p1')).type,
        isNot(ActionType.fold),
      );

      // 7-2 air facing a pot-sized bet -> below pot odds, folds.
      final trash = _facingBet(
        p0: cards('Ah Qd'),
        p1: cards('7c 2d'),
        flop: cards('Kh 8s 3c'),
        potFraction: 1.0,
      );
      expect(
        _pol(isaacHaxton).decide(trash, _p(trash, 'p1')).type,
        ActionType.fold,
      );
    });

    test('an exploitative pro applies more pressure than the GTO anchor (air)', () {
      // No bet to face, hero (p1) has air on a dry board.
      final g = _game(_stack(
        p0: cards('Ah Ad'),
        p1: cards('7c 2d'),
        flop: cards('Kh 8s 3c'),
      ));
      _toFlop(g);
      final hero = _p(g, 'p1');
      expect(g.callAmount(hero), 0);

      // haiLe: adherence 0.65, exploit 0.75 -> deviates; Haxton: adherence 1.0.
      final exploiter = _aggressiveRate(_pol(haiLe), g, hero, trials);
      final gto = _aggressiveRate(_pol(isaacHaxton), g, hero, trials);
      expect(exploiter, greaterThan(gto));
    });

    test('an exploitative pro semibluff-raises a draw more than the GTO anchor', () {
      // Hero (p1) holds a flush draw (two hearts) on a two-heart board, facing a
      // half-pot bet.
      PokerGame draw() => _facingBet(
            p0: cards('As Ks'),
            p1: cards('Qh Jh'),
            flop: cards('9h 4h 2c'),
            potFraction: 0.5,
          );
      final g1 = draw();
      final g2 = draw();
      final exploiter = _aggressiveRate(_pol(haiLe), g1, _p(g1, 'p1'), trials);
      final gto = _aggressiveRate(_pol(isaacHaxton), g2, _p(g2, 'p1'), trials);
      expect(exploiter, greaterThan(gto));
    });
  });
}
