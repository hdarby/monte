import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/tournament/domain/tournament_result.dart';

TournamentResult _ev(int buyIn, List<(String, int, int, bool)> f) =>
    TournamentResult(
      timestampMs: 1,
      structureName: 'Turbo',
      buyIn: buyIn,
      entrants: f.length,
      finishes: [
        for (final (id, place, prize, faced) in f)
          TournamentFinish(
              profileId: id,
              name: id,
              place: place,
              prize: prize,
              facedHuman: faced),
      ],
    );

void main() {
  test('ROI is measured against money in, not events played', () {
    // Two $100 events, one 500 cash: 200 in, 500 out, +150%.
    final rows = CareerRow.from([
      _ev(100, [('P1', 1, 500, true), ('P2', 2, 0, false)]),
      _ev(100, [('P2', 1, 500, false), ('P1', 2, 0, true)]),
    ]);
    final p1 = rows.firstWhere((r) => r.profileId == 'P1');
    expect(p1.played, 2);
    expect(p1.cashes, 1);
    expect(p1.cashRate, 50);
    expect(p1.buyIns, 200);
    expect(p1.won, 500);
    expect(p1.net, 300);
    expect(p1.roi, 150);
    expect(p1.bestPlace, 1);
    expect(p1.facedYou, 2, reason: 'both events shared a table');
  });

  test('accumulates by profile id, not by the generated name', () {
    // FieldBuilder renames duplicates, so names are not stable across events.
    final rows = CareerRow.from([
      _ev(100, [('P1', 1, 200, false)]),
      _ev(100, [('P1', 3, 0, false)]),
    ]);
    expect(rows, hasLength(1));
    expect(rows.first.played, 2);
  });

  test('a losing personality reports a negative ROI', () {
    final rows = CareerRow.from([_ev(1000, [('P9', 40, 0, false)])]);
    expect(rows.first.roi, -100);
    expect(rows.first.net, -1000);
  });
}
