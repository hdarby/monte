import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/preflop_ranges.dart';
import 'package:monte/core/domain/ai/profile_policy.dart';
import 'package:monte/core/domain/ai/profile_postflop_policy.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

import '../_helpers.dart';

// A pro-tier profile (skill 1.0) with the given characteristics attached.
PlayerProfile _pro(List<PlayerCharacteristic> chars) => PlayerProfile.fromJson({
      'id': 'T',
      'name': 'Test Pro',
      'archetype': 'test',
      'strategic_baseline': {
        'vpip_target': 0.30,
        'pfr_target': 0.24,
        'three_bet_frequency': 0.08,
        'gto_adherence_weight': 0.9,
      },
      'behavioral_modifiers': {
        'tilt_resistance': 0.9,
        'exploitative_weight': 0.3,
        'risk_premium_coefficient': 1.0,
        'weight_on_opponent_history': 0.5,
      },
      'engine_triggers': null,
      'skill': 1.0,
      'general_traits': {
        'position_awareness': 1.0,
        'pot_odds': 1.0,
        'implied_odds': 1.0,
      },
      'characteristics': [for (final c in chars) c.toJson()],
      'description': null,
    });

// Explicit mid-range preflop cutoffs so the positional skew has room either way.
const _ranges = PreflopRanges(vpip: 0.38, pfr: 0.46, threeBet: 0.62);

// Six-handed opens: seat 0 is the hero; everyone before it folds so the hero is
// first-in at the seat that [buttonIndex] implies. Returns whether the hero
// opens (raises) the given [hand].
bool _opens(ProfilePolicy pol, int buttonIndex, List<Card> hand) {
  final players = [
    for (var i = 0; i < 6; i++) Player(id: 'p$i', name: 'p$i', stack: 1000),
  ];
  final game = PokerGame(players: players, deck: Deck(random: Random(7)))
    ..buttonIndex = buttonIndex;
  game.startHand();
  players[0].hole
    ..clear()
    ..addAll(hand);
  // Fold around to the hero (seat 0).
  var guard = 0;
  while (!identical(game.currentPlayer, players[0]) && guard++ < 12) {
    game.applyAction(const GameAction.fold());
  }
  if (!identical(game.currentPlayer, players[0])) return false;
  return pol.decide(game, players[0]).type == ActionType.raise;
}

// Heads-up on the flop, hero (p1) first to act with no bet to face. Returns the
// fraction of [trials] the hero takes an aggressive (bet) line.
double _flopBetRate(PlayerProfile profile, {required int trials}) {
  var bets = 0;
  for (var t = 0; t < trials; t++) {
    final order = _headsUpFlop(
      hero: cards('Qc 9d'), // queen-high air on a dry board (a bluff/check spot)
      villain: cards('7s 4h'),
      flop: cards('Jh 5c 2d'),
    );
    final game = PokerGame(
      players: [
        Player(id: 'p0', name: 'P0', stack: 1000),
        Player(id: 'p1', name: 'P1', stack: 1000, isHuman: true),
      ],
      deck: Deck.stacked(order),
    )..startHand();
    while (game.round == BettingRound.preflop) {
      final p = game.currentPlayer!;
      game.applyAction(
          game.canCheck(p) ? const GameAction.check() : const GameAction.call());
    }
    final hero = game.players.firstWhere((x) => x.id == 'p1');
    final pol = ProfilePostflopPolicy(profile, random: Random(100 + t));
    final t0 = pol.decide(game, hero).type;
    if (t0 == ActionType.bet) bets++;
  }
  return bets / trials;
}

List<Card> _headsUpFlop({
  required List<Card> hero,
  required List<Card> villain,
  required List<Card> flop,
}) {
  final placed = <int, Card>{
    0: villain[0], 2: villain[1],
    1: hero[0], 3: hero[1],
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

// Heads-up with the hero (p1) on the button (in position postflop). The villain
// (p0) acts first and checks; returns whether the hero then bets, for a given
// deck seed so two profiles see identical boards.
bool _ipCheckBets(PlayerProfile profile, int seed) {
  final game = PokerGame(
    players: [
      Player(id: 'p0', name: 'P0', stack: 1000),
      Player(id: 'p1', name: 'P1', stack: 1000, isHuman: true),
    ],
    deck: Deck(random: Random(seed)),
  )
    ..buttonIndex = 1 // p1 is button/SB → in position postflop
    ..startHand();
  game.players[0].hole
    ..clear()
    ..addAll(cards('7s 4h'));
  game.players[1].hole
    ..clear()
    ..addAll(cards('Qc 9d')); // queen-high air: a check/bluff spot
  while (game.round == BettingRound.preflop) {
    final p = game.currentPlayer!;
    game.applyAction(
        game.canCheck(p) ? const GameAction.check() : const GameAction.call());
  }
  while (game.currentPlayer?.id == 'p0') {
    game.applyAction(const GameAction.check()); // villain shows weakness
  }
  if (game.currentPlayer?.id != 'p1') return false;
  final hero = game.players[1];
  return ProfilePostflopPolicy(profile, random: Random(seed * 7 + 1))
          .decide(game, hero)
          .type ==
      ActionType.bet;
}

// The hero's turn bet size as a fraction of the pot, holding a set (nut
// advantage) in position after a checked-through flop. 0 if it doesn't bet.
double _turnBetFraction(PlayerProfile profile) {
  final placed = <int, Card>{
    0: card('7h'), 2: card('4c'), // villain (overwritten below)
    1: card('As'), 3: card('Ad'), // hero (overwritten below)
    5: card('Ac'), 6: card('7s'), 7: card('2d'), // flop
    9: card('Ks'), // turn (index 4 & 8 are burns)
  };
  final used = placed.values.toSet();
  final rest = [
    for (final suit in Suit.values)
      for (final rank in Rank.values)
        if (!used.contains(Card(rank, suit))) Card(rank, suit),
  ];
  var r = 0;
  final order = [for (var i = 0; i < 52; i++) placed[i] ?? rest[r++]];
  final game = PokerGame(
    players: [
      Player(id: 'p0', name: 'P0', stack: 1000),
      Player(id: 'p1', name: 'P1', stack: 1000, isHuman: true),
    ],
    deck: Deck.stacked(order),
  )
    ..buttonIndex = 1
    ..startHand();
  game.players[0].hole
    ..clear()
    ..addAll(cards('7h 4c'));
  game.players[1].hole
    ..clear()
    ..addAll(cards('As Ad')); // top set on A-7-2
  while (game.round == BettingRound.preflop) {
    final p = game.currentPlayer!;
    game.applyAction(
        game.canCheck(p) ? const GameAction.check() : const GameAction.call());
  }
  while (game.round == BettingRound.flop) {
    game.applyAction(const GameAction.check()); // check through to the turn
  }
  while (game.currentPlayer?.id == 'p0') {
    game.applyAction(const GameAction.check());
  }
  final hero = game.players[1];
  final potBefore = game.pot;
  final act = ProfilePostflopPolicy(profile, random: Random(3)).decide(game, hero);
  if (act.type != ActionType.bet) return 0;
  return (act.amount - hero.currentBet) / potBefore;
}

// Hero (p1) faces a [potFraction] bet from the villain (p0) on the flop.
ActionType _facingBetAction(PlayerProfile profile, double potFraction) {
  final order = _headsUpFlop(
    hero: cards('9c 9d'), // underpair bluff-catcher on K-8-3
    villain: cards('Ah Qd'),
    flop: cards('Kh 8s 3c'),
  );
  final game = PokerGame(
    players: [
      Player(id: 'p0', name: 'P0', stack: 1000),
      Player(id: 'p1', name: 'P1', stack: 1000, isHuman: true),
    ],
    deck: Deck.stacked(order),
  )..startHand();
  while (game.round == BettingRound.preflop) {
    final p = game.currentPlayer!;
    game.applyAction(
        game.canCheck(p) ? const GameAction.check() : const GameAction.call());
  }
  game.applyAction(const GameAction.check()); // hero (OOP) checks
  final villain = game.currentPlayer!; // p0 bets
  game.applyAction(
      GameAction.bet(villain.currentBet + (game.pot * potFraction).round()));
  final hero = game.players.firstWhere((x) => x.id == 'p1');
  return ProfilePostflopPolicy(profile, random: Random(9)).decide(game, hero).type;
}

void main() {
  // A spread of marginal offsuit/broadway/suited hands around the open threshold.
  final hands = [
    'As 9d', 'Kh Td', 'Qc Jd', 'Ks 9h', 'Qh 9s', 'Jc Td', 'Ah 5s',
    'Kd Jc', 'Tc 9c', 'Qd Ts', 'Jh 9h', 'Ad 8d',
  ].map(cards).toList();

  group('Positional_Warfare', () {
    // Button = 0 makes seat 0 the button (latest, loosest); button = 3 makes
    // seat 0 UTG (earlier, tighter).
    const buttonSeat = 0;
    const utgSeat = 3;

    int opensAt(ProfilePolicy pol, int button) =>
        hands.where((h) => _opens(pol, button, h)).length;

    test('a positional pro opens more on the button than under the gun', () {
      final pol = ProfilePolicy(
        _pro([const PlayerCharacteristic(id: 'Positional_Warfare', proficiency: 0.9)]),
        ranges: _ranges,
        random: Random(1),
      );
      final onButton = opensAt(pol, buttonSeat);
      final underGun = opensAt(pol, utgSeat);
      expect(onButton, greaterThan(underGun),
          reason: 'positional warfare should open wider on the button');
    });

    test('without the characteristic, opens do not skew by seat', () {
      final pol = ProfilePolicy(_pro(const []), ranges: _ranges, random: Random(1));
      expect(opensAt(pol, buttonSeat), equals(opensAt(pol, utgSeat)),
          reason: 'no positional skew without the characteristic');
    });
  });

  group('Leverage_Pressure', () {
    test('a pressure pro bets a mediocre hand heads-up more than a baseline pro', () {
      const trials = 200;
      final pressure = _flopBetRate(
        _pro([const PlayerCharacteristic(id: 'Leverage_Pressure', proficiency: 0.9)]),
        trials: trials,
      );
      final baseline = _flopBetRate(_pro(const []), trials: trials);
      expect(pressure, greaterThan(baseline),
          reason: 'leverage pressure should fire more aggression heads-up');
    });
  });

  group('Soul_Read', () {
    test('ranges a bettor tighter: folds the bluff-catcher to a smaller bet', () {
      final reader = _pro(
          [const PlayerCharacteristic(id: 'Soul_Read', proficiency: 1.0)]);
      final baseline = _pro(const []);
      // Smallest bet (as a pot fraction) at which the pro folds 99 on K-8-3.
      double foldThreshold(PlayerProfile p) {
        for (var f = 0.4; f <= 3.01; f += 0.1) {
          if (_facingBetAction(p, f) == ActionType.fold) return f;
        }
        return 99;
      }
      // The sharper read credits the bettor with a tighter range, so it gives up
      // the bluff-catcher to a smaller bet than the baseline pro does.
      expect(foldThreshold(reader), lessThan(foldThreshold(baseline)),
          reason: 'soul read should fold to a smaller bet');
    });

    test('a soul-reader attacks a check in position more than a baseline pro', () {
      final seeds = [for (var i = 0; i < 200; i++) i + 1];
      final reader = _pro(
          [const PlayerCharacteristic(id: 'Soul_Read', proficiency: 0.9)]);
      final baseline = _pro(const []);
      final readerRate =
          seeds.where((s) => _ipCheckBets(reader, s)).length / seeds.length;
      final baseRate =
          seeds.where((s) => _ipCheckBets(baseline, s)).length / seeds.length;
      expect(readerRate, greaterThan(baseRate),
          reason: 'soul read should stab more when checked to in position');
    });
  });

  group('Geometric_Overbet_Execution', () {
    test('overbets a nut hand on the turn vs a standard-sizing baseline', () {
      final geo = _turnBetFraction(_pro([
        const PlayerCharacteristic(
            id: 'Geometric_Overbet_Execution', proficiency: 0.9)
      ]));
      final baseline = _turnBetFraction(_pro(const []));
      expect(baseline, greaterThan(0)); // both value-bet the set
      expect(geo, greaterThan(baseline),
          reason: 'geometric overbet should size up with a nut advantage');
      expect(geo, greaterThan(1.0),
          reason: 'a geometric overbet is larger than the pot');
    });
  });
}
