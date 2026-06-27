import 'package:flutter_test/flutter_test.dart';
import 'package:poker_client/core/domain/engine/actions.dart';
import 'package:poker_client/core/domain/engine/game.dart';
import 'package:poker_client/features/analytics/domain/analytics.dart';
import 'package:poker_client/core/domain/hand_history.dart';

ActionRecord _action(String id, BettingRound street, ActionType type) =>
    ActionRecord(playerId: id, street: street, type: type, amount: 0, potAfter: 0);

HandHistory _hand({
  required int number,
  required List<ActionRecord> actions,
  Map<String, int> finalStacks = const {},
}) {
  return HandHistory(
    handNumber: number,
    smallBlind: 5,
    bigBlind: 10,
    players: const [
      HandPlayer(
          id: 'a',
          name: 'A',
          startingStack: 1000,
          holeCards: ['As', 'Ks'],
          isButton: true),
      HandPlayer(
          id: 'b',
          name: 'B',
          startingStack: 1000,
          holeCards: ['2c', '7d'],
          isButton: false),
    ],
    actions: actions,
    board: const [],
    results: const [],
    finalStacks: finalStacks,
  );
}

void main() {
  group('PokerAnalytics', () {
    test('VPIP and PFR are counted per hand, not per action', () {
      final histories = [
        // Hand 1: A raises preflop (VPIP + PFR), B folds (neither).
        _hand(number: 1, actions: [
          _action('a', BettingRound.preflop, ActionType.raise),
          _action('b', BettingRound.preflop, ActionType.fold),
        ]),
        // Hand 2: A calls preflop (VPIP, not PFR), B raises (VPIP + PFR).
        _hand(number: 2, actions: [
          _action('a', BettingRound.preflop, ActionType.call),
          _action('b', BettingRound.preflop, ActionType.raise),
        ]),
      ];

      final stats = {for (final s in PokerAnalytics.compute(histories)) s.id: s};

      expect(stats['a']!.hands, 2);
      expect(stats['a']!.vpip, 100); // voluntary both hands
      expect(stats['a']!.pfr, 50); // raised only hand 1
      expect(stats['b']!.vpip, 50); // folded hand 1, raised hand 2
      expect(stats['b']!.pfr, 50);
    });

    test('aggression factor uses postflop bets/raises over calls', () {
      final histories = [
        _hand(number: 1, actions: [
          _action('a', BettingRound.flop, ActionType.bet),
          _action('a', BettingRound.turn, ActionType.raise),
          _action('a', BettingRound.river, ActionType.call),
          // Preflop aggression must NOT count toward AF.
          _action('a', BettingRound.preflop, ActionType.raise),
        ]),
      ];

      final a = PokerAnalytics.compute(histories).first;
      expect(a.aggressiveActions, 2);
      expect(a.callActions, 1);
      expect(a.aggressionFactor, 2.0);
      expect(a.aggressionLabel, '2.00');
    });

    test('infinite aggression when never calling', () {
      final histories = [
        _hand(number: 1, actions: [
          _action('a', BettingRound.flop, ActionType.bet),
        ]),
      ];
      final a = PokerAnalytics.compute(histories).first;
      expect(a.aggressionFactor, double.infinity);
      expect(a.aggressionLabel, '∞');
    });

    test('net chips and bb/100 from final stacks', () {
      final histories = [
        _hand(
          number: 1,
          actions: [_action('a', BettingRound.preflop, ActionType.raise)],
          finalStacks: {'a': 1100, 'b': 900},
        ),
      ];
      final stats = {for (final s in PokerAnalytics.compute(histories)) s.id: s};
      expect(stats['a']!.netChips, 100);
      expect(stats['b']!.netChips, -100);
      // 100 chips / 10 bb = 10 bb over 1 hand => 1000 bb/100.
      expect(stats['a']!.bbPer100, 1000);
    });
  });
}
