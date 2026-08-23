import 'package:monte/core/domain/ai/player_kind.dart';
import 'chip_set.dart';
import 'tournament_chronicle.dart';
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

/// The tournament standings' name for [PlayerKind]. Kept as an alias so the
/// standings and the table seats classify players with one shared enum.
typedef StandingKind = PlayerKind;

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
    this.kind = StandingKind.pro,
    this.generated = false,
  });
  final int place;
  final String name;
  final bool isHuman;

  /// The player's brain class (human / pro / amateur), for the standings tint.
  final StandingKind kind;

  /// True for an anonymous auto-filled field seat (vs an explicitly-chosen, real
  /// personality). Real personalities get a stronger tint so they stand out.
  final bool generated;

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
    this.tableBreak,
    this.yourTable = 0,
    this.recap,
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

  /// The table that just broke and where its players went, or null.
  final TableBreakDisplay? tableBreak;

  /// The table the human is seated at, numbered from **1**, or 0 when not
  /// seated.
  ///
  /// Internally tables are indexed from zero, which meant the human at table 0
  /// — everybody, in a single-table event — reported 0 and was treated as "no
  /// table", so the number never appeared at all. Real tournaments number
  /// tables from one; this is the display number, and 0 is the sentinel.
  final int yourTable;

  /// A recap for a level that just completed this tick, else null (one-shot).
  final LevelRecap? recap;

  /// Final standings once [status] is finished (best first), else null.
  final List<FinishRow>? finalResults;

  bool get finished => status == TournamentStatus.finished;

  /// The human's stack measured in big blinds — the number that actually drives
  /// tournament decisions. 0 when the level has no big blind yet.
  double get yourStackBb => bigBlind == 0 ? 0 : yourChips / bigBlind;

  /// The field's average stack in big blinds.
  double get averageStackBb => bigBlind == 0 ? 0 : averageStack / bigBlind;

  /// The human's stack as a percentage of the average (100 = exactly average).
  int get yourStackVsAveragePercent =>
      averageStack == 0 ? 0 : (yourChips / averageStack * 100).round();

  /// How many players must still bust before the money. 0 once in the money.
  int get playersToTheMoney =>
      inMoney ? 0 : (playersLeft - paidPlaces).clamp(0, playersLeft);

  /// Projects the current [state] for the human identified by [humanId].
  factory TournamentSnapshot.of(
    TournamentState state,
    String humanId, {
    ChipSet? chipSet,
    ColorUpEvent? colorUp,
    TableBreakDisplay? tableBreak,
    LevelRecap? recap,
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
      tableBreak: tableBreak,
      yourTable: _tableNumberOf(state, humanId),
      recap: recap,
      finalResults: results,
    );
  }
}

/// The human's table, numbered from 1, or 0 when they are not seated.
int _tableNumberOf(TournamentState state, String humanId) {
  for (final t in state.tables) {
    if (t.playerIds.contains(humanId)) return t.id + 1;
  }
  return 0;
}

/// A table that has just been broken, and where each of its players was sent.
///
/// Flavour, but the useful kind: a table breaking is one of the few moments in
/// a tournament where the field's shape becomes visible, and being told "table
/// 7 broke, you are now at table 3 seat 5" is how a player keeps their bearings.
class TableBreakDisplay {
  const TableBreakDisplay({required this.tableNumber, required this.moves});

  final int tableNumber;
  final List<TableBreakMove> moves;
}

class TableBreakMove {
  const TableBreakMove({
    required this.name,
    required this.isHuman,
    required this.toTable,
    required this.toSeat,
  });

  final String name;
  final bool isHuman;
  final int toTable;
  final int toSeat;
}
