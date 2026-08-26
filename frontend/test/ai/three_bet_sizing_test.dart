import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/open_ranges.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/profile_policy.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

import '../_helpers.dart';

const _pro = PlayerProfile(
  id: 'PRO1',
  name: 'Test Pro',
  archetype: 'Small_Ball_Hand_Reader',
  strategicBaseline: StrategicBaseline(
    vpipTarget: 0.24,
    pfrTarget: 0.195,
    threeBetFrequency: 0.08,
    gtoAdherenceWeight: 0.75,
  ),
  behavioralModifiers: BehavioralModifiers(
    tiltResistance: 0.7,
    exploitativeWeight: 0.3,
    riskPremiumCoefficient: 1.0,
    weightOnOpponentHistory: 0.3,
  ),
);

/// A 6-handed game, button fixed at seat 0, with [hero] holding [hole].
PokerGame _game({required int heroSeat, required List<Card> hole}) {
  final placed = <int, Card>{heroSeat: hole[0], heroSeat + 6: hole[1]};
  final used = placed.values.toSet();
  final rest = [
    for (final s in Suit.values)
      for (final r in Rank.values)
        if (!used.contains(Card(r, s))) Card(r, s),
  ];
  var i = 0;
  final order = [for (var k = 0; k < 52; k++) placed[k] ?? rest[i++]];
  return PokerGame(
    players: [
      for (var k = 0; k < 6; k++) Player(id: 'p$k', name: 'P$k', stack: 20000),
    ],
    smallBlind: 100,
    bigBlind: 200,
    deck: Deck.stacked(order),
    rotateButton: false,
  )..startHand();
}

void main() {
  group('OpenRanges.actsAfterPostflop', () {
    test('the button acts after everyone', () {
      final g = _game(heroSeat: 0, hole: cards('As Ks'));
      for (var i = 1; i < 6; i++) {
        expect(
          OpenRanges.actsAfterPostflop(g, g.players[0], g.players[i]),
          isTrue,
          reason: 'seat 0 is the button',
        );
      }
    });

    test('the small blind acts before everyone', () {
      final g = _game(heroSeat: 1, hole: cards('As Ks'));
      for (var i = 0; i < 6; i++) {
        if (i == 1) continue;
        expect(
          OpenRanges.actsAfterPostflop(g, g.players[1], g.players[i]),
          isFalse,
          reason: 'seat 1 is the small blind',
        );
      }
    });

    test('is antisymmetric between two seats', () {
      final g = _game(heroSeat: 0, hole: cards('As Ks'));
      final a = g.players[2], b = g.players[4];
      expect(OpenRanges.actsAfterPostflop(g, a, b),
          isNot(OpenRanges.actsAfterPostflop(g, b, a)));
    });
  });

  group('ProfilePolicy 3-bet sizing', () {
    /// Seat 3 (early) open-raises to 3x, folded to [heroSeat]. Returns the
    /// raise-to amount if the hero decides to 3-bet, otherwise null.
    int? threeBetSizeFor(int heroSeat) {
      final g = _game(heroSeat: heroSeat, hole: cards('As Ah'));
      // Seat 3 is UTG at a 6-max button-0 table (SB=1, BB=2, UTG=3). Fold
      // everyone up to it, have it open, then fold everyone up to hero.
      while (g.currentPlayer != null && g.currentPlayer!.id != 'p3') {
        g.applyAction(const GameAction.fold());
      }
      g.applyAction(GameAction.raise(600)); // 3x open
      while (g.currentPlayer != null &&
          g.currentPlayer!.id != 'p$heroSeat' &&
          g.currentPlayer!.inHand) {
        g.applyAction(const GameAction.fold());
      }
      if (g.currentPlayer?.id != 'p$heroSeat') return null;
      final action = ProfilePolicy(_pro).decide(g, g.currentPlayer!);
      return action.type == ActionType.raise ? action.amount : null;
    }

    test('an in-position 3-bet is smaller than an out-of-position one', () {
      // Button 0 ⇒ seat 3 is UTG, the opener. Seat 4 acts after it for the
      // rest of the hand (in position). Seat 1 is the small blind — first to
      // act every postflop street (out of position), even though it acted
      // last preflop.
      final ipSize = threeBetSizeFor(4);
      final oopSize = threeBetSizeFor(1);
      expect(ipSize, isNotNull);
      expect(oopSize, isNotNull);
      expect(ipSize, lessThan(oopSize!));
    });

    test('in position lands near 3x the open, out of position near 4x', () {
      const openTo = 600;
      final ipSize = threeBetSizeFor(4)!;
      final oopSize = threeBetSizeFor(1)!;
      expect(ipSize / openTo, closeTo(3.0, 0.5));
      expect(oopSize / openTo, closeTo(4.0, 0.6));
    });

    test('an aggressive personality 3-bets bigger than a nitty one, same seat',
        () {
      int? threeBetFor(PlayerProfile profile) {
        final g = _game(heroSeat: 4, hole: cards('As Ah'));
        while (g.currentPlayer != null && g.currentPlayer!.id != 'p3') {
          g.applyAction(const GameAction.fold());
        }
        g.applyAction(GameAction.raise(600));
        final action = ProfilePolicy(profile).decide(g, g.currentPlayer!);
        return action.type == ActionType.raise ? action.amount : null;
      }

      PlayerProfile withRisk(double r) => PlayerProfile(
            id: _pro.id,
            name: _pro.name,
            archetype: _pro.archetype,
            strategicBaseline: _pro.strategicBaseline,
            behavioralModifiers: BehavioralModifiers(
              tiltResistance: _pro.behavioralModifiers.tiltResistance,
              exploitativeWeight: _pro.behavioralModifiers.exploitativeWeight,
              riskPremiumCoefficient: r,
              weightOnOpponentHistory:
                  _pro.behavioralModifiers.weightOnOpponentHistory,
            ),
          );

      final nit = threeBetFor(withRisk(0.6))!;
      final base = threeBetFor(withRisk(1.0))!;
      final maniac = threeBetFor(withRisk(1.6))!;
      expect(nit, lessThan(base));
      expect(base, lessThan(maniac));
    });
  });
}
