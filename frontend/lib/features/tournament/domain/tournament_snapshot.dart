import 'chip_set.dart';
import 'tournament_state.dart';
import 'tournament_structure.dart';

/// Progress of the between-hands background simulation: how many of the other
/// tables have played their hand this round. [done] == [total] (or total 0)
/// means the round is complete and the UI can hide the progress bar.
class SimProgress {
  const SimProgress({required this.done, required this.total});
  final int done;
  final int total;

  bool get isRunning => total > 0 && done < total;
  double get fraction => total == 0 ? 1 : done / total;
}

/// One player's line in a color-up (chip race) result: their name and the chips
/// they gained (+) or lost (-) racing off their odd chips.
class ColorUpRow {
  const ColorUpRow(
      {required this.name, required this.isHuman, required this.delta});
  final String name;
  final bool isHuman;
  final int delta;
}

/// A completed color-up for the UI: the chip retired, the new smallest chip, and
/// who won/lost what (biggest swings first). Present only on the snapshot for
/// the single tick the race happened.
class ColorUpDisplay {
  const ColorUpDisplay(
      {required this.retiredUnit, required this.newUnit, required this.rows});
  final int retiredUnit;
  final int newUnit;
  final List<ColorUpRow> rows;
}

/// One line of the live standings list: every player ordered by place —
/// still-active players first (ranked by chips), then busted players by finish.
class StandingRow {
  const StandingRow({
    required this.place,
    required this.name,
    required this.isHuman,
    required this.chips,
    required this.busted,
    required this.prize,
  });
  final int place;
  final String name;
  final bool isHuman;

  /// Live chip count (0 once busted).
  final int chips;
  final bool busted;

  /// Prize won (busted-and-paid players only), else 0.
  final int prize;
}

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
    required this.smallestChip,
    this.colorUp,
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

  /// The smallest chip denomination currently in play (bet granularity).
  final int smallestChip;

  /// A color-up that just happened this tick, else null.
  final ColorUpDisplay? colorUp;

  /// Final standings once [status] is finished (best first), else null.
  final List<FinishRow>? finalResults;

  bool get finished => status == TournamentStatus.finished;

  /// Projects the current [state] for the human identified by [humanId].
  factory TournamentSnapshot.of(
    TournamentState state,
    String humanId, {
    ChipSet? chipSet,
    ColorUpEvent? colorUp,
  }) {
    final level = state.currentLevel;
    final chips = chipSet ?? ChipSet.wsop();
    final smallestChip = chips.smallestChip(
      smallBlind: level.smallBlind,
      bigBlind: level.bigBlind,
      ante: level.ante,
    );
    ColorUpDisplay? colorUpDisplay;
    if (colorUp != null && colorUp.deltas.isNotEmpty) {
      final rows = colorUp.deltas.entries
          .map((e) => ColorUpRow(
                name: state.players[e.key]?.name ?? e.key,
                isHuman: state.players[e.key]?.isHuman ?? false,
                delta: e.value,
              ))
          .toList()
        ..sort((a, b) => b.delta.compareTo(a.delta));
      colorUpDisplay = ColorUpDisplay(
          retiredUnit: colorUp.oldUnit, newUnit: colorUp.newUnit, rows: rows);
    }
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
      smallestChip: smallestChip,
      colorUp: colorUpDisplay,
      finalResults: results,
    );
  }
}
