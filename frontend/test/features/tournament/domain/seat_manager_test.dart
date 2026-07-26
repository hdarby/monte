import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/tournament/domain/payout_structure.dart';
import 'package:monte/features/tournament/domain/seat_manager.dart';
import 'package:monte/features/tournament/domain/tournament_state.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

// Build a state whose tables have the given sizes (players auto-named).
TournamentState _stateWithTables(List<int> tableSizes) {
  final players = <String, TournamentPlayer>{};
  final tables = <TournamentTable>[];
  var n = 0;
  for (var t = 0; t < tableSizes.length; t++) {
    final ids = <String>[];
    for (var s = 0; s < tableSizes[t]; s++) {
      final id = 'p${n++}';
      players[id] = TournamentPlayer(id: id, name: id, isHuman: false, chips: 1000);
      ids.add(id);
    }
    tables.add(TournamentTable(id: t, playerIds: ids));
  }
  return TournamentState(
    structure: TournamentStructure.standard(),
    payouts: PayoutStructure.forFieldSize(players.length),
    buyIn: 100,
    players: players,
    tables: tables,
  );
}

List<int> _sizes(TournamentState s) => [for (final t in s.tables) t.size]..sort();

void main() {
  group('SeatManager.seatDraw', () {
    test('seats everyone across the minimum number of balanced tables', () {
      final s = _stateWithTables([18]); // one big blob to redraw
      SeatManager(Random(1)).seatDraw(s, 6);
      expect(s.tables.length, 3);
      expect(_sizes(s), [6, 6, 6]);
      // Every player has a real table + seat.
      for (final p in s.players.values) {
        expect(p.tableId, greaterThanOrEqualTo(0));
        expect(p.seatIndex, greaterThanOrEqualTo(0));
      }
    });

    test('is deterministic for a given seed', () {
      List<String> draw(int seed) {
        final s = _stateWithTables([18]);
        SeatManager(Random(seed)).seatDraw(s, 6);
        return [for (final t in s.tables) t.playerIds.join(',')];
      }

      expect(draw(42), draw(42));
    });
  });

  group('SeatManager.rebalance', () {
    test('keeps table sizes within one of each other', () {
      final s = _stateWithTables([6, 6, 2]); // 14 players, ideal 3 tables
      final mgr = SeatManager(Random(1));
      mgr.rebalance(s, 6);
      final sizes = _sizes(s);
      expect(sizes.last - sizes.first, lessThanOrEqualTo(1));
      expect(s.tables.length, 3);
    });

    test('breaks a surplus table down to the ideal count', () {
      final s = _stateWithTables([4, 4, 4]); // 12 players, ideal 2 tables of 6
      SeatManager(Random(1)).rebalance(s, 6);
      expect(s.tables.length, 2);
      expect(_sizes(s), [6, 6]);
      // No player left stranded on a broken table.
      final seated = s.tables.fold<int>(0, (a, t) => a + t.size);
      expect(seated, 12);
    });

    test('is a no-op when already balanced', () {
      final s = _stateWithTables([6, 5]);
      final moves = SeatManager(Random(1)).rebalance(s, 6);
      expect(moves, isEmpty);
      expect(_sizes(s), [5, 6]);
    });
  });

  group('SeatManager.shouldGoHandForHand', () {
    test('fires on the bubble across multiple tables', () {
      // forFieldSize(18) pays... make playersRemaining == paidPlaces + 1.
      final s = _stateWithTables([18]);
      SeatManager(Random(1)).seatDraw(s, 6);
      // Bust down to the bubble.
      final ids = s.players.keys.toList();
      var i = 0;
      while (s.playersRemaining > s.paidPlaces + 1) {
        s.recordBustouts([ids[i++]]);
      }
      SeatManager(Random(1)).rebalance(s, 6);
      expect(s.onBubble, isTrue);
      final hfh = SeatManager(Random(1)).shouldGoHandForHand(s, 6);
      expect(hfh, s.tables.where((t) => t.size > 0).length > 1);
    });
  });
}
