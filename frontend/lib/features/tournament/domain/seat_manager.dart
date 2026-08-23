import 'dart:math';

import 'tournament_state.dart';

/// A single seat reassignment produced by [SeatManager.rebalance].
class SeatMove {
  const SeatMove({
    required this.playerId,
    required this.fromTable,
    required this.toTable,
    required this.toSeat,
  });

  final String playerId;
  final int fromTable;
  final int toTable;
  final int toSeat;
}

/// Owns table composition for a multi-table tournament: the opening seat draw and
/// the between-hands balancing (breaking short tables, keeping table sizes within
/// one of each other) plus the hand-for-hand bubble trigger. Deterministic given
/// the injected [Random].
class SeatManager {
  SeatManager(this.rng);

  final Random rng;

  int idealTableCount(int playersRemaining, int tableSize) =>
      playersRemaining <= 0 ? 0 : (playersRemaining / tableSize).ceil();

  /// True on the money bubble AND while players are spread across more than one
  /// table — the point at which every table must play hand-for-hand so nobody
  /// stalls into the money.
  bool shouldGoHandForHand(TournamentState s, int tableSize) {
    final tables = s.tables.where((t) => t.size > 0).length;
    return s.onBubble && tables > 1;
  }

  /// Randomly seats every entrant across the minimum number of tables. Mutates
  /// [s.tables] and each player's `tableId`/`seatIndex`.
  void seatDraw(TournamentState s, int tableSize) {
    final ids = s.players.keys.toList()..shuffle(rng);
    final tableCount = idealTableCount(ids.length, tableSize);
    final tables = [
      for (var t = 0; t < tableCount; t++)
        TournamentTable(id: t, playerIds: <String>[]),
    ];
    // Deal players round-robin so tables stay within one of each other.
    for (var i = 0; i < ids.length; i++) {
      tables[i % tableCount].playerIds.add(ids[i]);
    }
    s.tables = tables;
    _reindex(s);
  }

  /// Rebalances between hands: breaks surplus tables into the shortest ones, then
  /// evens out counts so no two tables differ by more than one. Returns the moves
  /// made (also applied to [s]).
  /// [protect] names tables that should be broken last — the feature tables.
  /// A real tournament keeps the table with the recognisable players together
  /// and breaks somebody else's; it is the one with cameras on it.
  List<SeatMove> rebalance(TournamentState s, int tableSize,
      {Set<int> protect = const {}}) {
    final moves = <SeatMove>[];
    var live = s.tables.where((t) => t.size > 0).toList();

    // 1. Break tables: if we have more than the ideal, empty the smallest into
    //    the others (shortest target first), until we're at the ideal count.
    var ideal = idealTableCount(s.playersRemaining, tableSize);
    while (live.length > ideal && live.length > 1) {
      // Smallest first, but a protected table sorts to the back so it is only
      // broken when nothing else is left to break.
      live.sort((a, b) {
        final pa = protect.contains(a.id) ? 1 : 0;
        final pb = protect.contains(b.id) ? 1 : 0;
        return pa != pb ? pa - pb : a.size.compareTo(b.size);
      });
      final breaking = live.first..isBreaking = true;
      final targets = live.sublist(1);
      for (final pid in List<String>.of(breaking.playerIds)) {
        targets.sort((a, b) => a.size.compareTo(b.size));
        final target = targets.first;
        moves.add(SeatMove(
          playerId: pid,
          fromTable: breaking.id,
          toTable: target.id,
          toSeat: target.size,
        ));
        breaking.playerIds.remove(pid);
        target.playerIds.add(pid);
      }
      breaking.isBreaking = false;
      live = live.where((t) => t.size > 0).toList();
      ideal = idealTableCount(s.playersRemaining, tableSize);
    }

    // 2. Balance counts: move one player at a time from the largest table to the
    //    smallest until the spread is at most one.
    while (live.length > 1) {
      live.sort((a, b) => a.size.compareTo(b.size));
      final smallest = live.first;
      final largest = live.last;
      if (largest.size - smallest.size <= 1) break;
      final pid = largest.playerIds.last; // the seat closest to moving is fine here
      moves.add(SeatMove(
        playerId: pid,
        fromTable: largest.id,
        toTable: smallest.id,
        toSeat: smallest.size,
      ));
      largest.playerIds.remove(pid);
      smallest.playerIds.add(pid);
    }

    s.tables = live;
    _reindex(s);
    return moves;
  }

  /// Writes each player's `tableId`/`seatIndex` from the current table seat lists.
  void _reindex(TournamentState s) {
    for (final t in s.tables) {
      for (var seat = 0; seat < t.playerIds.length; seat++) {
        final p = s.players[t.playerIds[seat]];
        if (p != null) {
          p.tableId = t.id;
          p.seatIndex = seat;
        }
      }
    }
  }
}
