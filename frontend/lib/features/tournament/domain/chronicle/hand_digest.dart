import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/features/tournament/domain/chronicle/hand_replay.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart'
    show StandingKind;

/// What the controller hands the chronicle after every completed hand.

/// One player's showing at a completed hand, as observed at the table (the
/// engine knows every hole card, so a recap of an *off-table* hand can honestly
/// report what was shown down). [aheadOnFlop] is true when this player held the
/// best hand among the all-in contenders as of the flop — used to tell a genuine
/// suck-out/bad-beat from a hand that was simply best throughout.
class ShowdownEntry {
  const ShowdownEntry({
    required this.id,
    required this.name,
    required this.kind,
    required this.wentAllIn,
    required this.net,
    required this.rank,
    this.aheadOnFlop = false,
  });

  final String id;
  final String name;
  final StandingKind kind;
  final bool wentAllIn;

  /// Chips won (+) or lost (-) this hand.
  final int net;

  /// The player's made hand at showdown, or null if they folded before it.
  final HandRank? rank;
  final bool aheadOnFlop;
}

/// A compact, fully-factual summary of one completed hand, handed to the
/// [TournamentChronicle]. Everything here is real engine output — no invention.
class HandDigest {
  const HandDigest({
    required this.levelIndex,
    required this.tableId,
    this.notables = const [],
    required this.pot,
    required this.showdown,
    required this.winners,
    required this.busted,
    this.humanTable = false,
    this.replay,
  });

  final int levelIndex;
  final int tableId;

  /// Named personalities sitting at this table — the ones with a real player
  /// behind them, as opposed to the anonymous profiles that fill out a field.
  ///
  /// Two or more of them makes it a **feature table**: the one a broadcast
  /// would put cameras on, and the one whose hands are worth showing.
  final List<String> notables;

  /// Total chips contested (won from opponents) this hand.
  final int pot;

  /// Players who reached showdown (empty when the hand ended on a fold).
  final List<ShowdownEntry> showdown;

  /// Ids of the winner(s).
  final List<String> winners;

  /// Ids eliminated this hand (busted).
  final List<String> busted;
  final bool humanTable;

  /// Full hand detail for a showdown (hole cards, board, street action), so the
  /// recap can replay the level's biggest pot. Null for folds / uncontested pots.
  final HandReplay? replay;
}
