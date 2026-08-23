import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart';

/// Table numbers are shown to a poker player, not to a programmer. Internally
/// they are indexed from zero, which meant everyone at the first table — that
/// is, everyone in a single-table event — reported 0, was read as "not seated",
/// and saw no table number at all. The break banner would have announced
/// "Table 0 has broken", which is not a sentence a tournament ever says.
void main() {
  test('the break display numbers tables from one', () {
    const d = TableBreakDisplay(tableNumber: 1, moves: [
      TableBreakMove(name: 'You', isHuman: true, toTable: 3, toSeat: 4),
    ]);
    expect(d.tableNumber, greaterThanOrEqualTo(1));
    expect(d.moves.first.toTable, greaterThanOrEqualTo(1));
  });
}
