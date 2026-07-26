import 'tournament_state.dart';
import 'tournament_structure.dart';

/// One finished player's result, for the standings/results screen.
class FinishRow {
  const FinishRow({
    required this.place,
    required this.name,
    required this.isHuman,
    required this.prize,
  });
  final int place;
  final String name;
  final bool isHuman;
  final int prize;
}

/// The tournament-wide state the HUD/lobby/results render — broadcast alongside
/// the live [TableSnapshot]. Flat and serializable, like the table snapshot, so a
/// server could send the same thing.
class TournamentSnapshot {
  const TournamentSnapshot({
    required this.status,
    required this.level,
    required this.levelIndex,
    required this.smallBlind,
    required this.bigBlind,
    required this.ante,
    required this.clockMode,
    required this.handsThisLevel,
    required this.handsPerLevel,
    required this.schedule,
    required this.playersLeft,
    required this.entrants,
    required this.tableCount,
    required this.averageStack,
    required this.totalChips,
    required this.startingStack,
    required this.prizePool,
    required this.buyIn,
    required this.paidPlaces,
    required this.payouts,
    required this.inMoney,
    required this.nextPayoutPlace,
    required this.nextPayoutAmount,
    required this.yourChips,
    required this.yourPlace,
    required this.youBusted,
    this.finalResults,
  });

  final TournamentStatus status;
  final int level;

  /// 0-based index of the active level in [schedule] (may exceed it once blinds
  /// are capped past the last defined level).
  final int levelIndex;
  final int smallBlind;
  final int bigBlind;
  final int ante;
  final LevelClockMode clockMode;
  final int handsThisLevel;
  final int handsPerLevel;

  /// The full blind ladder, for the level-detail popup.
  final List<BlindLevel> schedule;

  final int playersLeft;
  final int entrants;
  final int tableCount;
  final int averageStack;
  final int totalChips;
  final int startingStack;
  final int prizePool;
  final int buyIn;
  final int paidPlaces;

  /// Prize by place (index 0 = 1st), for the payout-detail popup.
  final List<int> payouts;
  final bool inMoney;

  /// The place the next bust-out finishes in, and what it pays (0 if unpaid).
  final int nextPayoutPlace;
  final int nextPayoutAmount;

  /// The human's live chip count and current standing (place if out, else their
  /// rank among the remaining by chips).
  final int yourChips;
  final int yourPlace;
  final bool youBusted;

  /// Final standings once [status] is finished (best first), else null.
  final List<FinishRow>? finalResults;

  bool get finished => status == TournamentStatus.finished;

  /// Projects the current [state] for the human identified by [humanId].
  factory TournamentSnapshot.of(TournamentState state, String humanId) {
    final level = state.currentLevel;
    final you = state.players[humanId];
    final payouts = state.payoutTable;
    final nextPlace = state.nextPayoutPlace;
    final nextAmount =
        (nextPlace >= 1 && nextPlace <= payouts.length) ? payouts[nextPlace - 1] : 0;

    // Your standing: finish place if out; otherwise your live chip rank.
    int yourPlace;
    if (you != null && you.finishPlace != null) {
      yourPlace = you.finishPlace!;
    } else if (you != null) {
      final richer = state.activePlayers.where((p) => p.chips > you.chips).length;
      yourPlace = richer + 1;
    } else {
      yourPlace = state.entrants;
    }

    List<FinishRow>? results;
    if (state.status == TournamentStatus.finished) {
      results = (state.players.values.toList()
            ..sort((a, b) => (a.finishPlace ?? 1 << 30)
                .compareTo(b.finishPlace ?? 1 << 30)))
          .map((p) => FinishRow(
                place: p.finishPlace ?? state.entrants,
                name: p.name,
                isHuman: p.isHuman,
                prize: p.prizeWon,
              ))
          .toList();
    }

    return TournamentSnapshot(
      status: state.status,
      level: level.level,
      levelIndex: state.levelIndex,
      smallBlind: level.smallBlind,
      bigBlind: level.bigBlind,
      ante: level.ante,
      clockMode: state.structure.clockMode,
      handsThisLevel: state.handsThisLevel,
      handsPerLevel: state.structure.durationOf(state.levelIndex),
      schedule: state.structure.levels,
      playersLeft: state.playersRemaining,
      entrants: state.entrants,
      tableCount: state.tables.where((t) => t.size > 0).length,
      averageStack: state.averageStack,
      totalChips: state.totalChips,
      startingStack: state.structure.startingStack,
      prizePool: state.prizePool,
      buyIn: state.buyIn,
      paidPlaces: state.paidPlaces,
      payouts: payouts,
      inMoney: state.inMoney,
      nextPayoutPlace: nextPlace,
      nextPayoutAmount: nextAmount,
      yourChips: you?.chips ?? 0,
      yourPlace: yourPlace,
      youBusted: you != null && !you.isActive,
      finalResults: results,
    );
  }
}
