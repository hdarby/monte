import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/push_fold_chart.dart';
import 'package:monte/core/domain/ai/tournament_context.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

/// Builds a heads-up hand where hero (11000 chips) faces a much shorter
/// villain stack all-in for its whole stack from the forced big blind alone —
/// hero has a real call decision (button/SB acts first heads-up), not a
/// shove one.
({PokerGame game, Player hero}) _facingShortAllIn({
  required int heroStack,
  required int villainStack,
  required int smallBlind,
  required int bigBlind,
  List<Card>? heroHole,
}) {
  final hero = Player(id: 'hero', name: 'Hero', stack: heroStack);
  final villain = Player(id: 'villain', name: 'Villain', stack: villainStack);
  final deck = heroHole == null
      ? Deck()
      : Deck.stacked([
          heroHole[0],
          Card.fromCode('2c'),
          heroHole[1],
          Card.fromCode('3d'),
        ]);
  final game = PokerGame(
    players: [hero, villain],
    smallBlind: smallBlind,
    bigBlind: bigBlind,
    deck: deck,
    rotateButton: false, // hero (index 0) is the button/SB
  )..startHand();
  return (game: game, hero: hero);
}

void main() {
  group('PushFoldChart', () {
    test('a genuine shove decision (toCall == 0) is unaffected by the '
        'pot-odds floor — still requires the full ICM-tightened cutoff', () {
      // Heads-up, SB limps (calls) so it becomes BB's decision with nothing
      // extra to call — a real "should I shove my whole stack" spot, not a
      // priced call.
      final hero = Player(id: 'hero', name: 'Hero', stack: 11000); // BB
      final sb = Player(id: 'sb', name: 'SB', stack: 11000);
      final game = PokerGame(
        players: [sb, hero],
        smallBlind: 3000,
        bigBlind: 6000,
        deck: Deck.stacked([
          Card.fromCode('8h'), Card.fromCode('3c'), // sb
          Card.fromCode('7h'), Card.fromCode('2c'), // hero: 72o, a weak hand
        ]),
        rotateButton: false,
      )..startHand();
      game.applyAction(const GameAction.call()); // SB limps to 6000

      expect(game.currentPlayer?.id, 'hero');
      expect(game.callAmount(hero), 0,
          reason: 'hero must be facing nothing to call, for this to '
              'actually be the shove-or-fold path');

      const ctx = TournamentContext(
        stackInBb: 1.83,
        bubbleFactor: 5.0, // Icm.bubbleFactor's real ceiling
        playersLeft: 2,
        paidPlaces: 1,
        inMoney: true,
      );
      final action = const PushFoldChart().decide(game, hero, ctx);
      expect(action.type, ActionType.check,
          reason: '72o should never shove under max ICM pressure with '
              'nothing forcing the decision (check, since there is nothing '
              'to fold) — untouched by the pot-odds floor, which only '
              'applies when toCall > 0');
    });

    test('a trivially-priced call (opponent all-in for a fraction of the '
        'effective stack) is not blocked by a maxed-out ICM bubble factor',
        () {
      final spot = _facingShortAllIn(
        heroStack: 11000,
        villainStack: 1000, // ~9x shorter — a near-free call for hero
        smallBlind: 3000,
        bigBlind: 6000,
        heroHole: [Card.fromCode('Ah'), Card.fromCode('As')], // AA: ~0.95
      );
      expect(spot.game.currentPlayer?.id, 'hero');
      expect(spot.game.callAmount(spot.hero), greaterThan(0),
          reason: 'this must actually be a real call decision');

      const ctx = TournamentContext(
        stackInBb: 1.83,
        bubbleFactor: 5.0, // the real ceiling — this is the regression case
        playersLeft: 2,
        paidPlaces: 1,
        inMoney: true,
      );
      // Before the pot-odds floor, this cutoff computed to ~0.9166 (clamped
      // to 0.9) — AA (~0.95) was the *only* hand able to clear it, and this
      // exact scenario, unfixed, is what pinned real tournaments at exactly
      // this chip ratio for the entire 200k-hand safety net in half of a
      // 10-seed sweep. With the floor, real pot odds (~43% breakeven) plus a
      // modest ICM margin bring the bar down to ~63% — comfortably cleared
      // by AA, so this specific regression case is fixed.
      final action = const PushFoldChart().decide(spot.game, spot.hero, ctx);
      expect(action.type, isNot(ActionType.fold),
          reason: 'AA facing an overwhelmingly-priced call must not fold to '
              'a maxed-out bubble factor pinning the flat cutoff near 0.9');
    });

    test('the same shape of call folds a real hand under max ICM pressure '
        'once the price stops being trivial', () {
      // Villain's stack is a much larger fraction of hero's now — pot odds
      // alone no longer justify calling with anything, so the flat
      // ICM-tightened cutoff should still bite.
      const ctx = TournamentContext(
        stackInBb: 1.83,
        bubbleFactor: 5.0,
        playersLeft: 2,
        paidPlaces: 1,
        inMoney: true,
      );
      // Run across a spread of random hands (default shuffle) rather than
      // asserting a single seed's result — just confirming folding is still
      // reachable at this price, proving the floor didn't turn the chart
      // into "always call."
      var sawFold = false;
      for (var i = 0; i < 30; i++) {
        final trial = _facingShortAllIn(
          heroStack: 11000,
          villainStack: 9000, // most of hero's stack — a real shove-off
          smallBlind: 3000,
          bigBlind: 6000,
        );
        final action = const PushFoldChart().decide(trial.game, trial.hero, ctx);
        if (action.type == ActionType.fold) sawFold = true;
      }
      expect(sawFold, isTrue,
          reason: 'the pot-odds floor must not eliminate folding entirely '
              'once a call is genuinely expensive again');
    });
  });
}
