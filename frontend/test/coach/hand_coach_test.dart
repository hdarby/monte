import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/features/coach/domain/hand_coach.dart';

import '../_helpers.dart';

HandCoachInput _input({
  required String hole,
  String board = '',
  int pot = 100,
  int toCall = 0,
  int heroCurrentBet = 0,
  int currentBet = 0,
  int effectiveStack = 1000,
  int bigBlind = 10,
  BettingRound street = BettingRound.flop,
  int raiseCount = 0,
  int opponents = 1,
  bool canCheck = true,
  bool canRaise = true,
  int minRaiseTo = 10,
  int maxRaiseTo = 1000,
  int seed = 1,
}) => HandCoachInput(
  hole: cards(hole),
  board: board.isEmpty ? const <Card>[] : cards(board),
  pot: pot,
  toCall: toCall,
  heroCurrentBet: heroCurrentBet,
  currentBet: currentBet,
  effectiveStack: effectiveStack,
  bigBlind: bigBlind,
  street: street,
  raiseCount: raiseCount,
  opponents: opponents,
  opponentLabels: const ['Villain'],
  canCheck: canCheck,
  canRaise: canRaise,
  minRaiseTo: minRaiseTo,
  maxRaiseTo: maxRaiseTo,
  random: Random(seed),
);

void main() {
  group('HandCoach', () {
    test('a monster in an unopened pot is played aggressively', () {
      // Top set on a dry flop, checked to hero.
      final r = HandCoach.analyze(
        _input(hole: 'As Ac', board: 'Ad Kh 7c'),
        analysisAvailable: true,
      );
      expect(r.equity, greaterThan(0.85));
      final rec = r.actions[r.recommendedIndex];
      expect(rec.kind, anyOf(CoachAction.bet, CoachAction.raise));
      expect(r.breakdown!.beat, greaterThan(0.7));
    });

    test('trash facing a big all-in should fold (call is -EV)', () {
      final r = HandCoach.analyze(
        _input(
          hole: '7c 2d',
          board: 'As Kd Qh',
          pot: 200,
          toCall: 100,
          currentBet: 100,
          canCheck: false,
          canRaise: false, // facing a shove: fold or call only
        ),
        analysisAvailable: true,
      );
      final call = r.actions.firstWhere((a) => a.kind == CoachAction.call);
      expect(call.ev, lessThan(0));
      expect(r.actions[r.recommendedIndex].kind, CoachAction.fold);
      expect(r.breakdown!.lose, greaterThan(0.5));
    });

    test('call EV follows pot-odds; +EV when equity beats the odds', () {
      final r = HandCoach.analyze(
        _input(
          hole: 'Ah Kd', // middling equity on this board
          board: 'Qs Jc 2d',
          pot: 100,
          toCall: 25,
          currentBet: 25,
          canCheck: false,
          canRaise: false,
        ),
        analysisAvailable: true,
      );
      final call = r.actions.firstWhere((a) => a.kind == CoachAction.call);
      // Formula check: eq*pot - (1-eq)*toCall.
      expect(call.ev, closeTo(r.equity * 100 - (1 - r.equity) * 25, 0.6));
      expect(r.potOdds, closeTo(0.2, 0.001));
      if (r.equity > r.potOdds!) expect(call.ev, greaterThan(0));
    });

    test('multiway discounts equity (more opponents = less equity)', () {
      final one = HandCoach.analyze(
        _input(hole: 'Ah Kh', board: 'Qh 7c 2d', opponents: 1),
        analysisAvailable: true,
      );
      final three = HandCoach.analyze(
        _input(hole: 'Ah Kh', board: 'Qh 7c 2d', opponents: 3),
        analysisAvailable: true,
      );
      expect(three.equity, lessThan(one.equity));
    });

    test('preflop hand labels', () {
      String label(String hole) => HandCoach.analyze(
        _input(hole: hole, street: BettingRound.preflop),
        analysisAvailable: true,
      ).madeHand;
      expect(label('As Ks'), 'AKs');
      expect(label('Ts 7c'), 'T7o');
      expect(label('Th Td'), 'pocket tens');
    });

    test('flags a polarized spot on a big river bet', () {
      final river = HandCoach.analyze(
        _input(
          hole: 'Ah Ad',
          board: 'Kd Qs 7c 3h 2d',
          pot: 300,
          toCall: 150,
          currentBet: 150,
          street: BettingRound.river,
          raiseCount: 1,
          canCheck: false,
        ),
        analysisAvailable: true,
      );
      expect(river.polarized, isTrue);
      expect(river.polarizedNote, isNotNull);

      final flopSmall = HandCoach.analyze(
        _input(
          hole: 'Ah Ad',
          board: 'Kd Qs 7c',
          pot: 120,
          toCall: 20,
          currentBet: 20,
          canCheck: false,
        ),
        analysisAvailable: true,
      );
      expect(flopSmall.polarized, isFalse);
    });

    test('short stack collapses sizes and offers an all-in', () {
      final r = HandCoach.analyze(
        _input(
          hole: 'As Ac',
          board: 'Ad Kh 7c',
          pot: 100,
          minRaiseTo: 90,
          maxRaiseTo: 120, // little room → sizes clamp together
        ),
        analysisAvailable: true,
      );
      final bets =
          r.actions.where((a) => a.toAmount != null).toList();
      // No duplicate bet-to amounts survive.
      final tos = bets.map((a) => a.toAmount).toList();
      expect(tos.toSet().length, tos.length);
      expect(bets.any((a) => a.sizingTag == 'all-in'), isTrue);
    });

    test('stats-only when it is not the hero turn', () {
      final r = HandCoach.analyze(
        _input(hole: 'As Ac', board: 'Ad Kh 7c'),
        analysisAvailable: false,
      );
      expect(r.actions, isEmpty);
      expect(r.recommendedIndex, -1);
      expect(r.equity, greaterThan(0)); // stats still computed
    });
  });
}
