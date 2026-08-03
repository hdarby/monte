import 'payout_structure.dart';
import 'tournament_structure.dart';

/// Whether a player is still in the tournament.
enum PlayerStatus { active, busted, sittingOut }

/// The lifecycle of the whole tournament.
enum TournamentStatus { registering, running, handForHand, finished }

/// One entrant's live tournament state. Mutable — the controller updates chips,
/// seat, and status between hands (mirrors the mutable `PokerGame` engine).
class TournamentPlayer {
  TournamentPlayer({
    required this.id,
    required this.name,
    required this.isHuman,
    required this.chips,
    this.tableId = -1,
    this.seatIndex = -1,
    this.status = PlayerStatus.active,
    this.rebuysUsed = 0,
    this.finishPlace,
    this.prizeWon = 0,
  });

  final String id;
  final String name;
  final bool isHuman;
  int chips;
  int tableId;
  int seatIndex;
  PlayerStatus status;
  int rebuysUsed;

  /// 1-indexed finish place once out (or 1 for the champion); null while active.
  int? finishPlace;
  int prizeWon;

  bool get isActive => status == PlayerStatus.active;
}

/// One table's seat order (a list of player ids, seat 0 first).
class TournamentTable {
  TournamentTable({required this.id, required this.playerIds, this.isBreaking = false});

  final int id;
  List<String> playerIds;
  bool isBreaking;

  int get size => playerIds.length;
}

/// The live tournament aggregate — "what a server would broadcast". Owns the
/// blind level/clock counters, the tables, every player, the finish order, and
/// the prize pool. Pure data + the small rules that mutate it (bustouts, level
/// progression, rebuys); table balancing lives in `SeatManager` and the clock is
/// ticked by the controller.
class TournamentState {
  TournamentState({
    required this.structure,
    required this.payouts,
    required this.buyIn,
    required this.players,
    required this.tables,
    this.levelIndex = 0,
    this.handsThisLevel = 0,
    this.clockElapsed = Duration.zero,
    List<String>? finishOrder,
    int? prizePool,
    this.status = TournamentStatus.running,
  })  : finishOrder = finishOrder ?? [],
        prizePool = prizePool ?? buyIn * players.length,
        _activeCount = players.values.where((p) => p.isActive).length;

  final TournamentStructure structure;
  final PayoutStructure payouts;
  final int buyIn;

  final Map<String, TournamentPlayer> players;
  List<TournamentTable> tables;

  int levelIndex;
  int handsThisLevel;
  Duration clockElapsed;

  /// Bust order, worst finish first (index 0 finished last). The champion is
  /// appended last when the tournament ends.
  final List<String> finishOrder;
  int prizePool;
  TournamentStatus status;

  // ---- Derived views -------------------------------------------------------

  /// Live count of active players, maintained incrementally (bustouts/rebuys) so
  /// [playersRemaining] is O(1) — it's read once per bot decision in huge fields,
  /// where an O(entrants) scan would dominate the whole simulation.
  int _activeCount;

  Iterable<TournamentPlayer> get activePlayers =>
      players.values.where((p) => p.isActive);
  int get playersRemaining => _activeCount;
  int get entrants => players.length;
  int get totalChips => activePlayers.fold(0, (s, p) => s + p.chips);
  int get averageStack =>
      playersRemaining == 0 ? 0 : (totalChips / playersRemaining).round();

  BlindLevel get currentLevel => structure.levelAt(levelIndex);
  int get paidPlaces => payouts.paidPlaces;

  /// The place the next player to bust will finish in.
  int get nextPayoutPlace => playersRemaining;
  bool get inMoney => playersRemaining <= paidPlaces;

  /// True on the money bubble: one bustout away from everyone being paid.
  bool get onBubble => playersRemaining == paidPlaces + 1;

  /// The full payout vector for the current prize pool (index 0 = 1st).
  List<int> get payoutTable => payouts.payouts(prizePool);

  // ---- Rules ---------------------------------------------------------------

  /// Records one or more simultaneous bustouts. [idsWorstFirst] must be ordered
  /// worst-to-best (fewest chips at the start of the hand first), so the first
  /// id takes the lowest (worst) open place. Assigns finish place + any prize,
  /// marks them busted, and removes them from their table's seat list.
  ///
  /// [removeFromTables] scans every table to drop the seat; set it false during
  /// large-field attrition, where tables are abstract and rebuilt at the reseat
  /// (the O(tables) scan per bust is the cost that made huge fields crawl).
  void recordBustouts(List<String> idsWorstFirst, {bool removeFromTables = true}) {
    var place = playersRemaining;
    for (final id in idsWorstFirst) {
      final p = players[id];
      if (p == null || !p.isActive) continue;
      p.status = PlayerStatus.busted;
      _activeCount--;
      p.chips = 0;
      p.finishPlace = place;
      p.prizeWon = payouts.payoutForPlace(place, prizePool);
      finishOrder.add(id);
      if (removeFromTables) {
        for (final t in tables) {
          t.playerIds.remove(id);
        }
      }
      place--;
    }
  }

  /// Ends the tournament: the last active player is the champion (place 1).
  void declareChampion() {
    final winner = activePlayers.isEmpty ? null : activePlayers.first;
    if (winner != null) {
      winner.finishPlace = 1;
      winner.prizeWon = payouts.payoutForPlace(1, prizePool);
      finishOrder.add(winner.id);
    }
    status = TournamentStatus.finished;
  }

  /// A rebuy / re-entry for [id]: tops the stack to [chips], grows the pool by
  /// the buy-in, and reactivates a busted entrant. Returns false if disallowed
  /// (freezeout, past the re-entry period, or the player is out of rebuys).
  bool rebuy(String id, {required int chips}) {
    final p = players[id];
    if (p == null) return false;
    if (!structure.allowsRebuys) return false;
    if (currentLevel.level > structure.reentryLevelCutoff) return false;
    if (p.rebuysUsed >= structure.maxRebuys) return false;
    if (!p.isActive) _activeCount++;
    p.chips = chips;
    p.rebuysUsed++;
    p.status = PlayerStatus.active;
    p.finishPlace = null;
    p.prizeWon = 0;
    finishOrder.remove(id);
    prizePool += buyIn;
    return true;
  }

  /// Advances the blind level if the active clock threshold has been crossed,
  /// resetting the per-level counters. Returns true if the level changed.
  bool maybeAdvanceLevel() {
    final needed = structure.durationOf(levelIndex);
    final crossed = switch (structure.clockMode) {
      LevelClockMode.hands => handsThisLevel >= needed,
      LevelClockMode.minutes => clockElapsed.inMinutes >= needed,
    };
    if (!crossed) return false;
    levelIndex++;
    handsThisLevel = 0;
    clockElapsed = Duration.zero;
    return true;
  }
}
