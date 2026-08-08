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

    test('bet size disciplines calls: bluff-catcher calls small, folds overbet', () {
      // Hero (p1) holds 99 on K-8-3 rainbow — an underpair bluff-catcher. It has
      // real equity against a normal continuing range but is crushed by the
      // polarized range behind a huge overbet. The GTO anchor (adherence 1.0)
      // plays pot odds straight, so this isolates the perceived-range effect.
      PokerGame spot(double potFraction) => _facingBet(
            p0: cards('Ah Qd'),
            p1: cards('9c 9d'),
            flop: cards('Kh 8s 3c'),
            potFraction: potFraction,
          );

      // A modest half-pot bet: continue.
      final small = spot(0.5);
      expect(
        _pol(isaacHaxton).decide(small, _p(small, 'p1')).type,
        isNot(ActionType.fold),
        reason: 'should call a normal bet with a bluff-catcher',
      );

      // A 3x-pot overbet: the perceived range collapses to premiums, equity
      // craters below pot odds — the "obvious fold" that used to get hero-called.
      final overbet = spot(3.0);
      expect(
        _pol(isaacHaxton).decide(overbet, _p(overbet, 'p1')).type,
        ActionType.fold,
        reason: 'should fold the same hand to a 3x-pot overbet',
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

      // danielNegreanu: adherence 0.65, exploit 0.75 -> deviates; Haxton: adherence 1.0.
      final exploiter = _aggressiveRate(_pol(danielNegreanu), g, hero, trials);
      final gto = _aggressiveRate(_pol(isaacHaxton), g, hero, trials);
      expect(exploiter, greaterThan(gto));
    });

    test('a pro folds a low flush into a bloated multiway pot', () {
      // 3-handed on a three-heart board. Hero (p2) makes a low flush; two other
      // players jam a bloated pot ahead of them — in multiway heavy action a
      // higher flush is very likely, so the pro lets the dominated hand go.
      // Deal order (3 players): holes 0,1,2 then 3,4,5; burn 6; flop 7,8,9.
      List<Card> stack3({required List<Card> hero}) {
        final placed = <int, Card>{
          0: cards('As Ks')[0], 3: cards('As Ks')[1], // p0
          1: cards('Ad Kd')[0], 4: cards('Ad Kd')[1], // p1
          2: hero[0], 5: hero[1], // p2 (hero)
          7: cards('Qh 9h 2h')[0],
          8: cards('Qh 9h 2h')[1],
          9: cards('Qh 9h 2h')[2],
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

      PokerGame spot(List<Card> heroHole) {
        final g = PokerGame(
          players: [
            Player(id: 'p0', name: 'P0', stack: 120),
            Player(id: 'p1', name: 'P1', stack: 120),
            Player(id: 'p2', name: 'P2', stack: 120, isHuman: true),
          ],
          deck: Deck.stacked(stack3(hero: heroHole)),
        )..startHand();
        _toFlop(g);
        // Two opponents build a bloated pot ahead of the hero (a near stack-off).
        while (g.currentPlayer!.id != 'p2') {
          final a = g.currentPlayer!;
          g.applyAction(g.callAmount(a) == 0
              ? GameAction.bet(a.currentBet + (g.pot * 3.0).round())
              : const GameAction.call());
        }
        return g;
      }

      // 5h4h → a Q-9-5-4-2 flush, dominated by every higher live heart. Two
      // opponents live in a bloated pot: fold.
      final low = spot(cards('5h 4h'));
      final hero = _p(low, 'p2');
      expect(low.players.where((x) => x.inHand && x.id != 'p2').length, 2);
      expect(
        _pol(isaacHaxton).decide(low, hero).type,
        ActionType.fold,
        reason: 'a low flush multiway into heavy action should fold',
      );
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
      final exploiter = _aggressiveRate(_pol(danielNegreanu), g1, _p(g1, 'p1'), trials);
      final gto = _aggressiveRate(_pol(isaacHaxton), g2, _p(g2, 'p1'), trials);
      expect(exploiter, greaterThan(gto));
    });
  });
}
