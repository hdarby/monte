import 'package:monte/core/util/format.dart';
import 'package:monte/features/tournament/domain/chronicle/hand_replay.dart';

/// The generated recap shown between levels, and its constituent lines.

/// A headline pot from a level, with the hands that were shown down.
class NotablePot {
  const NotablePot({
    required this.levelIndex,
    required this.tableId,
    required this.pot,
    required this.winnerName,
    required this.winnerHand,
    required this.loserName,
    required this.loserHand,
    required this.allIn,
    required this.suckout,
    required this.humanTable,
  });
  final int levelIndex;
  final int tableId;
  final int pot;
  final String winnerName;
  final String winnerHand;
  final String loserName;
  final String loserHand;
  final bool allIn;
  final bool suckout;
  final bool humanTable;

  /// Narrates the pot as a sentence, e.g. "Ann's flush beat Bo's straight for
  /// 250,000 (125 BB) at your table. Ann got there on the river."
  ///
  /// Lives here rather than in the recap widget so *all* recap prose is
  /// generated in the domain and stays testable without Flutter.
  String describe(int bigBlind) {
    final buf = StringBuffer()
      ..write(
        '$winnerName\'s ${winnerHand.toLowerCase()} '
        'beat $loserName\'s ${loserHand.toLowerCase()} '
        'for ${formatChipsWithBb(pot, bigBlind)}',
      );
    if (humanTable) buf.write(' at your table');
    buf.write('.');
    if (suckout) {
      buf.write(' $winnerName got there on the river.');
    } else if (allIn) {
      buf.write(' All in.');
    }
    return buf.toString();
  }
}

/// One line of the chip-leader board in a recap.
class ChipLeaderLine {
  const ChipLeaderLine({
    required this.name,
    required this.chips,
    required this.delta,
    required this.isHuman,
  });
  final String name;
  final int chips;
  final int delta;
  final bool isHuman;
}

/// A generated recap for one completed level — everything the UI needs to draw
/// the "level N in the books" card. All content is derived from real results.
class LevelRecap {
  const LevelRecap({
    required this.levelJustFinished,
    required this.playersLeft,
    required this.eliminatedThisLevel,
    required this.averageStack,
    required this.bigBlind,
    required this.intro,
    required this.bubbleLine,
    required this.chipLeaders,
    required this.biggestPots,
    required this.eliminations,
    required this.risers,
    required this.fallers,
    required this.leaderFollowUp,
    required this.bountyLine,
    required this.notables,
    required this.featureHand,
    this.featureTable,
    required this.yourStory,
    this.yourPlayStyle = const [],
    this.debugBustRates,
  });
  final int levelJustFinished;
  final int playersLeft;
  final int eliminatedThisLevel;
  final int averageStack;

  /// The big blind of the level recapped (for expressing stacks in BBs).
  final int bigBlind;

  /// Lead line: field size + this level's eliminations.
  final String intro;

  /// Money-bubble tension, or null when it's not near.
  final String? bubbleLine;
  final List<ChipLeaderLine> chipLeaders;
  final List<NotablePot> biggestPots;

  /// Named personalities who busted this level (with cash notes when ITM).
  final List<String> eliminations;

  /// Named personalities running deep (top 100), hyped.
  final List<String> risers;

  /// Named personalities on short stacks, struggling.
  final List<String> fallers;

  /// A follow-up on the previous level's chip leader, or null.
  final String? leaderFollowUp;

  /// The remaining knockout (bounty) leader, or null.
  final String? bountyLine;

  /// Table-bully / comeback / hand-driven storylines (hot / coolered / KO).
  final List<String> notables;

  /// A full replay (with commentary) of the level's biggest showdown, or null.
  final HandReplay? featureHand;

  /// Set when the feature hand came from a table with two or more named
  /// personalities — the one a broadcast would have had cameras on.
  final FeatureTable? featureTable;
  final String? yourStory;

  /// Concrete, numbers-included lines about how the human played this level
  /// (VPIP rate, steal rate, luck) — see `TournamentChronicle._yourPlayStyleLines`.
  final List<String> yourPlayStyle;

  /// TEMP diagnostic (bust rate by skill tier), not a real recap feature —
  /// see `TournamentChronicle._debugBustRatesByKind`. Remove alongside it.
  final String? debugBustRates;
}

/// The table the feature hand came from, when it was a notable one.
class FeatureTable {
  const FeatureTable({
    required this.number,
    required this.names,
    required this.humanSeated,
  });

  /// Display number, from 1.
  final int number;

  /// The recognisable players sitting there.
  final List<String> names;

  /// Whether the player was in the seat next to them.
  final bool humanSeated;
}
