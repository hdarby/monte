import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/eval_history/domain/session_markdown.dart';
import 'package:monte/features/eval_history/domain/session_report.dart';
import 'package:monte/features/eval_history/presentation/session_review_screen.dart';

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
      rfiBySeat: const {'UTG': (11, 3), 'BTN': (2, 2)},
      foldToThreeBet: 0,
      faced3Bet: 1,
      fourBet: 0,
      fiveBet: 0,
      squeeze: 0,
      bbDefend: 0,
      bbFacedSteal: 0,
      limpFolded: 0,
      riverFoldBySize: const {'1/3-2/3': (4, 1)},
      evLostByStreet: const {'preflop': 1.0, 'flop': 2.0, 'turn': 3.0, 'river': 4.0},
      evLostByAction: const {'call': 7.0, 'bet': 3.0},
      bustout: null,
      sessionId: 'T123',
      decisionCount: 177,
    );

void main() {
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

  testWidgets('the reader renders headings and tables, not raw pipes',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SessionReviewScreen(markdown: SessionMarkdown.of(_r())),
    ));
    expect(find.text('Red line / blue line'), findsOneWidget);
    expect(find.byType(Table), findsWidgets);
    // Bold and italic markers must be consumed, not displayed.
    expect(find.textContaining('**'), findsNothing);
    expect(find.textContaining('|---'), findsNothing);
  });
}
