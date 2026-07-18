import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/actions.dart';
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

    test('AJo UTG open: a small raise, never a 100bb shove', () {
      // First to act preflop, deep. Shoving into a 4-chip pot only gets called
      // by the very top of the range, so it must be badly -EV — the earlier bug
      // scored the shove against a loose range and (wrongly) recommended it.
      final r = HandCoach.analyze(
        _input(
          hole: 'Ah Jc',
          street: BettingRound.preflop,
          pot: 4,
          toCall: 3,
          currentBet: 3,
          canCheck: false,
          raiseCount: 0,
          opponents: 1,
          minRaiseTo: 6,
          maxRaiseTo: 296, // ~100bb deep
        ),
        analysisAvailable: true,
      );
      final rec = r.actions[r.recommendedIndex];
      // Recommend opening small, not jamming.
      expect(rec.kind, anyOf(CoachAction.raise, CoachAction.call));
      expect(rec.sizingTag, isNot('all-in'));
      // The shove is present but clearly -EV.
      final jam = r.actions.firstWhere((a) => a.sizingTag == 'all-in');
      expect(jam.ev, lessThan(0));
      // EV should not increase with bet size here (bigger = tighter callers).
      final raises = r.actions.where((a) => a.kind == CoachAction.raise).toList();
      for (var k = 1; k < raises.length; k++) {
        expect(raises[k].ev, lessThanOrEqualTo(raises[k - 1].ev + 0.5));
      }
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

    test('range grid: labels, ahead/behind colouring, and out cells', () {
      final r = HandCoach.analyze(
        _input(hole: 'As Ac', board: 'Ad Kh 7c'),
        analysisAvailable: true,
      );
      final g = r.handGrid!;
      expect(g.cells.length, 169);
      // Canonical chart corners.
      expect(g.cells[0].label, 'AA');
      expect(g.cells[1].label, 'AKs');
      expect(g.cells[13].label, 'AKo');
      // Some hands are in the perceived range, some are not.
      expect(g.cells.any((c) => c.inRange), isTrue);
      expect(g.cells.any((c) => c.status == CellStatus.out), isTrue);
      // Trip aces are ahead of most of the range they can hold.
      final ahead = g.cells.where((c) => c.status == CellStatus.ahead).length;
      final behind = g.cells.where((c) => c.status == CellStatus.behind).length;
      expect(ahead, greaterThan(behind));
    });

    test('range grid preflop shades the range without ahead/behind', () {
      final r = HandCoach.analyze(
        _input(hole: 'As Ks', street: BettingRound.preflop),
        analysisAvailable: true,
      );
      final g = r.handGrid!;
      expect(g.cells.any((c) => c.inRange), isTrue);
      expect(
        g.cells.every((c) =>
            c.status != CellStatus.ahead && c.status != CellStatus.behind),
        isTrue,
      );
    });

    test('suggestions map to concrete engine actions', () {
      final r = HandCoach.analyze(
        _input(
          hole: 'As Ac',
          board: 'Ad Kh 7c',
          pot: 100,
          minRaiseTo: 90,
          maxRaiseTo: 120, // little room → an all-in size appears
        ),
        analysisAvailable: true,
      );
      for (final a in r.actions) {
        final g = a.toGameAction();
        switch (a.kind) {
          case CoachAction.fold:
            expect(g.type, ActionType.fold);
          case CoachAction.check:
            expect(g.type, ActionType.check);
          case CoachAction.call:
            expect(g.type, ActionType.call);
          case CoachAction.bet:
          case CoachAction.raise:
            if (a.sizingTag == 'all-in') {
              expect(g.type, ActionType.allIn);
            } else {
              expect(g.type, anyOf(ActionType.bet, ActionType.raise));
              expect(g.amount, a.toAmount);
            }
        }
      }
    });

    test('AKo on the button facing a raise + call is a raise, not a fold', () {
      // Button with AKo, MP has opened and the HJ called (raiseCount 1, two
      // opponents in with a range). This should be a comfortable raise.
      final r = HandCoach.analyze(
        _input(
          hole: 'As Kd',
          street: BettingRound.preflop,
          pot: 19, // blinds 3 + open 8 + call 8
          toCall: 8,
          currentBet: 8,
          canCheck: false,
          raiseCount: 1,
          opponents: 2,
        ),
        analysisAvailable: true,
      );
      // Equity must be realistic for AKo three-way vs a ~20% range, not the
      // ~18% the old equity^opponents bug produced.
      expect(r.equity, greaterThan(0.33));
      // Calling clears the pot odds, and the recommendation is aggressive.
      final call = r.actions.firstWhere((a) => a.kind == CoachAction.call);
      expect(call.ev, greaterThan(0));
      expect(
        r.actions[r.recommendedIndex].kind,
        anyOf(CoachAction.bet, CoachAction.raise),
      );
    });

    test('KTo facing a big 4-bet does not shove — fold equity collapses', () {
      final r = HandCoach.analyze(
        _input(
          hole: 'Kh Td',
          street: BettingRound.preflop,
          pot: 220, // open+3bet+4bet already in
          toCall: 120,
          currentBet: 160,
          heroCurrentBet: 40,
          canCheck: false,
          raiseCount: 3, // facing a 4-bet
          opponents: 1,
          minRaiseTo: 320,
          maxRaiseTo: 1000, // room to jam
        ),
        analysisAvailable: true,
      );
      // KTo is crushed by a 4-bet range, so it should not be a value shove.
      expect(r.actions[r.recommendedIndex].kind, isNot(CoachAction.raise));
      // The all-in's EV must be negative (no meaningful fold equity vs a 4-bet).
      final jam = r.actions.where((a) => a.sizingTag == 'all-in');
      if (jam.isNotEmpty) expect(jam.first.ev, lessThan(0));
    });

    test('a big first bet still carries real fold equity', () {
      // Same big size, but leading into an unraised pot (raiseCount 0): fold
      // equity should NOT be gutted — the raise-count clamp only bites when the
      // opponent has already shown aggression.
      final r = HandCoach.analyze(
        _input(
          hole: 'Ah Kh',
          board: 'Qh 7c 2d',
          pot: 100,
          toCall: 0,
          currentBet: 0,
          canCheck: true,
          raiseCount: 0,
          minRaiseTo: 10,
          maxRaiseTo: 1000,
        ),
        analysisAvailable: true,
      );
      final bets = r.actions.where((a) => a.kind == CoachAction.bet);
      expect(bets, isNotEmpty);
      // Fold equity is mentioned and non-trivial for a bet into no aggression.
      expect(bets.any((a) => (a.note ?? '').contains('Fold equity')), isTrue);
    });

    test('raises are scored vs the tighter continuing range, not the wide one',
        () {
      // Facing a 3-bet on the flop: the range that continues vs our raise is
      // tighter than the current range, so the raise's "when called" equity
      // must be no higher than our headline equity.
      final r = HandCoach.analyze(
        _input(
          hole: 'Ah Qs',
          board: 'Qd 8c 3h',
          pot: 200,
          toCall: 60,
          currentBet: 60,
          canCheck: false,
          raiseCount: 2,
          opponents: 1,
          minRaiseTo: 180,
          maxRaiseTo: 1000,
        ),
        analysisAvailable: true,
      );
      final raise = r.actions.firstWhere(
        (a) => a.kind == CoachAction.raise,
        orElse: () => r.actions.last,
      );
      // The note carries "when called, Y% of a ... pot" — parse Y.
      final m = RegExp(r'when called, (\d+)%').firstMatch(raise.note ?? '');
      expect(m, isNotNull);
      final calledPct = int.parse(m!.group(1)!);
      // Continuing-range equity must not exceed the wider current-range equity
      // (allow a small Monte-Carlo margin).
      expect(calledPct, lessThanOrEqualTo((r.equity * 100).round() + 3));
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
