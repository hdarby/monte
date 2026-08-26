import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/eval_history/domain/duplicate_run.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';
import 'package:monte/features/eval_history/domain/session_markdown.dart';
import 'package:monte/features/eval_history/domain/session_report.dart';
import 'package:monte/features/eval_history/presentation/session_review_screen.dart';
import 'package:monte/features/tournament/domain/tournament_result.dart';

EvalHand _hand({required int number, List<String> board = const []}) => EvalHand(
      handNumber: number,
      smallBlind: 1,
      bigBlind: 2,
      players: const [
        EvalHandPlayer(
          id: 'e0',
          name: 'You',
          modelId: 'human',
          modelLabel: 'human',
          position: 'BTN',
          seatsFromButton: 0,
          holeCards: ['Ah', 'Kh'],
          startingStack: 200,
          finalStack: 200,
          folded: false,
        ),
      ],
      actions: const [],
      board: board,
      results: const [],
    );

DuplicateReport _duplicate({double yours = -10, double theirs = 15}) =>
    DuplicateReport(
      substituteName: 'Negreanu',
      runsPerHand: 120,
      hands: [
        DuplicateHand(hand: _hand(number: 1), yoursBb: yours, theirsBb: theirs),
      ],
    );

SessionReport _r({
  double net = -85,
  double allIn = -85,
  double nonShowdown = 418,
  int limps = 0,
}) =>
    SessionReport(
      playerId: 'e0',
      hands: 103,
      netBb: net,
      allInEvBb: allIn,
      showdownBb: -502,
      nonShowdownBb: nonShowdown,
      sawFlop: 27,
      wonWhenSawFlop: 12,
      vpip: 31,
      pfr: 18,
      threeBet: 1,
      limpFirstIn: limps,
      firstInSpots: 35,
      sbFirstIn: 9,
      sbComplete: 4,
      rfiBySeat: const {'UTG': (14, 11, 3), 'BTN': (5, 2, 2), 'BB': (12, 0, 0)},
      foldToThreeBet: 0,
      faced3Bet: 1,
      fourBet: 0,
      fiveBet: 0,
      squeeze: 0,
      bbDefend: 4,
      bbFacedSteal: 10,
      stealChances: 20,
      stealAttempts: 7,
      stealWins: 4,
      sbFacedSteal: 8,
      sbDefend: 2,
      sbThreeBet: 1,
      bbThreeBet: 2,
      limpFolded: 0,
      riverFoldBySize: const {'1/3-2/3': (4, 1)},
      evLostByStreet: const {'preflop': 1.0, 'flop': 2.0, 'turn': 3.0, 'river': 4.0},
      evLostByAction: const {'call': 7.0, 'bet': 3.0},
      bustout: null,
      sessionId: 'T123',
      decisionCount: 177,
    );

const _sample = '# Title\n\n## Section\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n- a **bold** point and an _aside_\n';

void main() {
  group('the duplicate-run section, standalone', () {
    test('duplicateSection contains no scaffolding from a whole report', () {
      // The regression: this used to come from a full SessionMarkdown.of(...)
      // call wrapping a throwaway zero-hand report, which wrote "# Baseline",
      // "0 hands", and empty Result/Red-line/Rules sections regardless — none
      // of those are gated on hands > 0. Appended to the real report, it read
      // as a second, broken report glued onto the end of the first.
      final section = SessionMarkdown.duplicateSection(_duplicate());
      expect(section, isNot(contains('# Baseline')));
      expect(section, isNot(contains('0 hands')));
      expect(section, isNot(contains('## Result')));
      expect(section, isNot(contains('## Red line')));
      expect(section, isNot(contains('## The rules')));
      expect(section, contains('If Negreanu had your cards'));
    });

    test('is empty when there are no duplicate hands', () {
      expect(
        SessionMarkdown.duplicateSection(
          const DuplicateReport(substituteName: 'Negreanu', runsPerHand: 120, hands: []),
        ),
        isEmpty,
      );
    });

    test('of(...) embeds the identical fragment when a duplicate is passed '
        'alongside a real report', () {
      final full = SessionMarkdown.of(_r(), duplicate: _duplicate());
      final fragment = SessionMarkdown.duplicateSection(_duplicate());
      expect(full, contains(fragment));
    });
  });

  group('this event\'s own finish', () {
    test('is absent for a cash-table session (no place given)', () {
      final md = SessionMarkdown.of(_r());
      expect(md, isNot(contains('Finished')));
      expect(md, isNot(contains('won it')));
    });

    test('reports place, field size and payout', () {
      final md = SessionMarkdown.of(_r(), place: 42, entrants: 180, prize: 340);
      expect(md, contains('Finished 42nd of 180'));
      expect(md, contains(r'$340'));
    });

    test('reports a bustout with no payout as "no cash"', () {
      final md = SessionMarkdown.of(_r(), place: 812, entrants: 1500, prize: 0);
      expect(md, contains('Finished 812th of 1500'));
      expect(md, contains('no cash'));
    });

    test('1st place reads as winning it, not "finished 1st"', () {
      final md = SessionMarkdown.of(_r(), place: 1, entrants: 9, prize: 4500);
      expect(md, contains('You won it'));
      expect(md, isNot(contains('Finished 1st')));
    });

    test('is separate from and precedes the career aggregate', () {
      final md = SessionMarkdown.of(
        _r(),
        place: 3,
        entrants: 20,
        prize: 900,
        career: const [
          CareerRow(
            profileId: 'human',
            name: 'You',
            played: 5,
            cashes: 2,
            buyIns: 500,
            won: 900,
            bestPlace: 3,
            facedYou: 0,
          ),
        ],
      );
      expect(md.indexOf('Finished 3rd'), lessThan(md.indexOf('## Career')));
    });
  });

  test('names the luck verdict rather than leaving it to the reader', () {
    expect(SessionMarkdown.of(_r()), contains('this result is real'));
    expect(SessionMarkdown.of(_r(net: -200, allIn: -85)),
        contains('ran below expectation'));
  });

  test('reads the blue line for the player', () {
    expect(SessionMarkdown.of(_r()), contains('aggression paying'));
    expect(SessionMarkdown.of(_r(nonShowdown: -109)),
        contains('not taking pots away'));
  });

  test('prints every metric beside the band it should be in', () {
    // A number with no target is trivia; a number with one is coaching.
    final md = SessionMarkdown.of(_r());
    for (final target in ['0%', '~23%', '~18%', '45-50%', '50-60%']) {
      expect(md, contains(target));
    }
  });

  test('shows the previous session for comparison when given one', () {
    final md = SessionMarkdown.of(_r(), previous: _r(limps: 16));
    expect(md, contains('was 45.7'));
  });

  test('bands are split so a shrinking tournament is not pooled', () {
    // 23% VPIP nine-handed and 80% heads-up average to something describing
    // neither, and the average looks like a mild leak rather than two games
    // played correctly.
    final md = SessionMarkdown.of(_r(), bands: [
      ('9-10 handed', _r()),
      ('Heads-up', _r()),
    ]);
    expect(md, contains('## By table size'));
    expect(md, contains('| 9-10 handed | 103 |'));
    expect(md, contains('| Heads-up | 103 |'));
    expect(md, contains('## All tables pooled'));
    expect(md.indexOf('By table size'), lessThan(md.indexOf('All tables pooled')),
        reason: 'the trustworthy split must come before the pooled figures');
  });

  test('a band with too few hands is hidden rather than shown as noise', () {
    final thin = SessionReport.of(const [], 'e0');
    final md = SessionMarkdown.of(_r(), bands: [('Heads-up', thin)]);
    expect(md, isNot(contains('## By table size')));
  });

  test('the career page puts you first, then the field by ROI', () {
    // You are reading this to find out how *you* are doing; hunting for your
    // own row among two hundred personalities would be absurd.
    const rows = [
      CareerRow(profileId: 'P1', name: 'Ivey', played: 9, cashes: 5,
          buyIns: 900, won: 4000, bestPlace: 1, facedYou: 3),
      CareerRow(profileId: 'human', name: 'You', played: 9, cashes: 1,
          buyIns: 900, won: 300, bestPlace: 14, facedYou: 9),
    ];
    final md = SessionMarkdown.of(_r(), career: rows);
    expect(md, contains('## Career'));
    expect(md.indexOf('**You**'), lessThan(md.indexOf('Ivey')));
    expect(md, contains('-\$600'), reason: 'a losing net reads as a loss');
    expect(md, contains('+344%'), reason: "Ivey's ROI on 900 in, 4000 out");
    expect(md, contains('measured against money in'));
  });

  test('leads with a verdict, worst first, and names one thing to fix', () {
    // The report was all evidence and no conclusion; six tables of frequencies
    // leave the reader to work out which number matters.
    final md = SessionMarkdown.of(_r());
    expect(md, contains('## The verdict'));
    expect(md, contains('Fix next:'));
    // The verdict has to come before the evidence, or it is just a footer.
    expect(md.indexOf('## The verdict'), lessThan(md.indexOf('## Result')));
  });

  test('the small blind is not counted as an open-limp', () {
    // Completing the small blind is often correct, and pooling it with an
    // under-the-gun limp makes a good play read as the same leak.
    final md = SessionMarkdown.of(_r());
    expect(md, contains('Open-limp (first in, not SB)'));
    expect(md, contains('SB complete (folded to you)'));
    expect(md, contains('often right'));
  });

  test('reports both sides of the blind battle', () {
    final md = SessionMarkdown.of(_r());
    expect(md, contains('Steal attempt'));
    expect(md, contains('35% of 20'));      // 7 of 20
    expect(md, contains('60% of 10'));      // BB folded 6 of 10
    expect(md, contains('75% of 8'));       // SB folded 6 of 8
    expect(md, contains('worse odds'));     // says why SB folds more
  });

  test('shows every seat sat in, including ones never opened from', () {
    // A missing seat is ambiguous: "never raised here" and "never had the
    // option here" are different facts and only one is a leak. The big blind
    // can never be first in, so it must read 0 chances rather than vanish.
    final md = SessionMarkdown.of(_r());
    expect(md, contains('| BB | 12 | 0 | 0 | — |'));
    expect(md, contains('| UTG | 14 | 11 | 3 |'));
    // Table order, not frequency order — a curve is unreadable otherwise.
    expect(md.indexOf('| UTG |'), lessThan(md.indexOf('| BTN |')));
    expect(md.indexOf('| BTN |'), lessThan(md.indexOf('| BB |')));
  });

  testWidgets('the reader renders markdown rather than showing its markers',
      (tester) async {
    // Rendered directly rather than through the screen: the review is long and
    // the screen's list is lazy, so anything below the fold is never built and
    // an assertion on it would prove nothing either way.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ListView(
            children: renderMarkdown(context, _sample),
          ),
        ),
      ),
    ));
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Section'), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
    expect(find.textContaining('|---'), findsNothing);
  });

  testWidgets('the review screen leads with the verdict', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SessionReviewScreen(markdown: SessionMarkdown.of(_r())),
    ));
    expect(find.text('The verdict'), findsOneWidget);
  });

  group('the duplicate-run progress row', () {
    // The row is appended after the whole (long) report, so a plain pump
    // never builds it — `ListView` only builds slivers near the viewport.
    // Scrolling to the key is what a user scrolling down would also have to
    // do, and is what makes the row actually exist in the widget tree.
    Future<void> scrollToProgressRow(WidgetTester tester) =>
        tester.scrollUntilVisible(
          find.byKey(const Key('duplicateProgressRow')),
          500,
          scrollable: find.byType(Scrollable).first,
        );

    testWidgets('the rest of the report is visible immediately, before the '
        'pending section resolves', (tester) async {
      // The report must never wait on the slow section — this is the literal
      // "don't hang the UI" requirement, and it's checked by never letting the
      // pending future complete during the test.
      final never = Completer<String>();
      await tester.pumpWidget(MaterialApp(
        home: SessionReviewScreen(
          markdown: SessionMarkdown.of(_r()),
          pending: never.future,
          progress: ValueNotifier<(int, int)>((0, 103)),
        ),
      ));
      await tester.pump();
      expect(find.text('The verdict'), findsOneWidget);
      await scrollToProgressRow(tester);
      expect(find.textContaining('0 of 103'), findsOneWidget);
    });

    testWidgets('shows real counts and updates as they change', (tester) async {
      final never = Completer<String>();
      final progress = ValueNotifier<(int, int)>((0, 50));
      await tester.pumpWidget(MaterialApp(
        home: SessionReviewScreen(
          markdown: SessionMarkdown.of(_r()),
          pending: never.future,
          progress: progress,
        ),
      ));
      await tester.pump();
      await scrollToProgressRow(tester);
      expect(find.textContaining('0 of 50'), findsOneWidget);

      progress.value = (17, 50);
      await tester.pump();
      expect(find.textContaining('17 of 50'), findsOneWidget);
      expect(find.textContaining('0 of 50'), findsNothing);
    });

    testWidgets('falls back to an indeterminate spinner with no progress '
        'tracker', (tester) async {
      final never = Completer<String>();
      await tester.pumpWidget(MaterialApp(
        home: SessionReviewScreen(
          markdown: SessionMarkdown.of(_r()),
          pending: never.future,
        ),
      ));
      await tester.pump();
      await scrollToProgressRow(tester);
      expect(find.textContaining('Replaying your hands'), findsOneWidget);
      expect(find.textContaining(' of '), findsNothing);
    });

    testWidgets('disappears once the pending section resolves', (tester) async {
      final completer = Completer<String>();
      await tester.pumpWidget(MaterialApp(
        home: SessionReviewScreen(
          markdown: SessionMarkdown.of(_r()),
          pending: completer.future,
          progress: ValueNotifier<(int, int)>((103, 103)),
        ),
      ));
      await tester.pump();
      await scrollToProgressRow(tester);
      expect(find.textContaining('Replaying your hands'), findsOneWidget);

      completer.complete('## Extra section\n');
      await tester.pump();
      expect(find.textContaining('Replaying your hands'), findsNothing);
      expect(find.text('Extra section'), findsOneWidget);
    });
  });
}
