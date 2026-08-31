import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/ai/trigger_observer.dart';
import 'package:monte/core/domain/engine/game.dart' show BettingRound;
import 'package:monte/core/domain/engine/hand_evaluator.dart';

/// A full, factual replay of one hand, used to show the level's biggest pot and
/// to feed the commentary in `hand_narrator.dart`.
///
/// Everything here is real engine output. The narrator adds prose on top but
/// never invents facts.

/// A seat's position at the table, in order of action preflop.
enum TablePosition {
  smallBlind('SB', 'the small blind'),
  bigBlind('BB', 'the big blind'),
  underTheGun('UTG', 'under the gun'),
  underTheGun1('UTG+1', 'UTG+1'),
  middle('MP', 'middle position'),
  middle1('MP+1', 'middle position'),
  lojack('LJ', 'the lojack'),
  hijack('HJ', 'the hijack'),
  cutoff('CO', 'the cutoff'),
  button('BTN', 'the button');

  const TablePosition(this.label, this.phrase);

  /// Short badge shown in the roster, e.g. "CO".
  final String label;

  /// Prose form for commentary, e.g. "the cutoff".
  final String phrase;

  /// True for positions that act last postflop and can play a wider, more
  /// aggressive game.
  bool get isLate =>
      this == TablePosition.button ||
      this == TablePosition.cutoff ||
      this == TablePosition.hijack;

  /// The blinds, which are out of position postflop for the rest of the hand.
  bool get isBlind =>
      this == TablePosition.smallBlind || this == TablePosition.bigBlind;

  /// A sane opening frequency for this seat, as a fraction of all hands. Used
  /// to judge whether an entry was too loose. The blinds are judged on
  /// defending frequency rather than opening.
  double get openingFrequency => switch (this) {
    TablePosition.underTheGun => 0.14,
    TablePosition.underTheGun1 => 0.16,
    TablePosition.middle => 0.18,
    TablePosition.middle1 => 0.20,
    TablePosition.lojack => 0.22,
    TablePosition.hijack => 0.26,
    TablePosition.cutoff => 0.32,
    TablePosition.button => 0.48,
    TablePosition.smallBlind => 0.35,
    TablePosition.bigBlind => 0.55,
  };
}

/// One action inside a replayed hand, with the context needed to judge it.
class ReplayAction {
  const ReplayAction({
    required this.playerId,
    required this.name,
    required this.position,
    required this.type,
    required this.street,
    required this.amount,
    required this.potBefore,
    required this.toCall,
    required this.isAllIn,
  });

  final String playerId;
  final String name;
  final TablePosition position;
  final ActionType type;
  final BettingRound street;

  /// For bet/raise the total "to" amount; for call the chips paid; else 0.
  final int amount;

  /// Pot size before this action went in.
  final int potBefore;

  /// What it cost this player to continue when they acted.
  final int toCall;

  final bool isAllIn;

  bool get isAggressive =>
      type == ActionType.bet ||
      type == ActionType.raise ||
      (type == ActionType.allIn && amount > toCall);

  bool get isFold => type == ActionType.fold;

  /// The bet as a fraction of the pot it went into — the number that decides
  /// whether a sizing was small, standard or an overbet.
  double get potFraction =>
      potBefore <= 0 ? 0 : (amount - toCall).clamp(0, 1 << 30) / potBefore;
}

/// One street of a replayed hand: the board after it was dealt, the action, and
/// the commentary on it.
class ReplayStreet {
  const ReplayStreet({
    required this.name,
    required this.round,
    required this.boardAfter,
    required this.actions,
    required this.potAfter,
    this.triggers = const [],
    this.commentary = const [],
  });

  final String name;
  final BettingRound round;

  /// Every board card face-up once this street was dealt (card codes).
  final List<String> boardAfter;

  final List<ReplayAction> actions;

  /// Pot size at the end of the street.
  final int potAfter;

  /// Signature moves that fired on this street (see `TriggerObserver`), so the
  /// commentary can name the move a player just made rather than describing it
  /// as an anonymous check or call.
  final List<FiredTrigger> triggers;

  /// Bart's read on this street, added by the narrator.
  final List<String> commentary;

  /// Human-readable action, e.g. "Ann raises to 2.5bb, Bob calls, Chen folds".
  /// Built by the narrator so sizes can be expressed in big blinds.
  ReplayStreet withCommentary(List<String> lines) => ReplayStreet(
    name: name,
    round: round,
    boardAfter: boardAfter,
    actions: actions,
    potAfter: potAfter,
    triggers: triggers,
    commentary: lines,
  );
}

/// A player who saw the flop, as shown in the hand's roster.
class ReplaySeat {
  const ReplaySeat({
    required this.playerId,
    required this.name,
    required this.cards,
    required this.position,
    required this.startingStack,
    required this.won,
    required this.net,
    required this.styleLabel,
    required this.foldedOn,
    required this.finalRank,
  });

  final String playerId;
  final String name;

  /// Two card codes, e.g. `['Ah','Kd']`.
  final List<String> cards;

  final TablePosition position;

  /// Chips this player had at the start of the hand.
  final int startingStack;

  final bool won;

  /// Chips won (+) or lost (-) on this hand.
  final int net;

  /// The player's personality in a word ("LAG", "nit", "calling station"), or
  /// null for the human / an untracked seat. Lets the commentary connect a play
  /// to how that player generally plays.
  final String? styleLabel;

  /// The street this player folded on, or null if they reached showdown.
  final BettingRound? foldedOn;

  /// The hand they finished with, or null if they folded before showdown.
  final HandRank? finalRank;

  bool get reachedShowdown => foldedOn == null;

  /// Starting stack in big blinds, given the level's [bigBlind].
  double stackBb(int bigBlind) =>
      bigBlind <= 0 ? 0 : startingStack / bigBlind;
}

/// Bart's closing verdict on one player's performance in the hand.
class PlayerVerdict {
  const PlayerVerdict({
    required this.name,
    required this.position,
    required this.line,
    required this.grade,
  });

  final String name;
  final TablePosition position;

  /// The verdict itself, e.g. "played it perfectly — value bet three streets".
  final String line;

  final VerdictGrade grade;
}

/// How well a player handled the hand, for colour-coding the summary.
enum VerdictGrade {
  excellent,
  good,
  standard,
  questionable,
  poor,
  unlucky,
}

/// A full, factual replay of one hand for the recap.
class HandReplay {
  const HandReplay({
    required this.pot,
    required this.bigBlind,
    required this.board,
    required this.seats,
    required this.streets,
    required this.winnerName,
    required this.winnerHand,
    required this.loserName,
    required this.loserHand,
    required this.winnerRank,
    required this.loserRank,
    required this.allIn,
    required this.suckout,
    required this.reachedRiver,
    this.equityWhenAllIn,
    this.headline,
    this.commentary = const [],
    this.verdicts = const [],
  });

  final int pot;

  /// The level's big blind, so every amount can be shown in BB.
  final int bigBlind;

  /// Strategic headline describing the key theme (e.g., "Pro collision", "Suckout").
  final String? headline;

  final List<String> board;

  /// Everyone who saw the flop, in position order.
  final List<ReplaySeat> seats;

  final List<ReplayStreet> streets;

  final String winnerName;
  final String winnerHand;
  final String loserName;
  final String loserHand;
  final HandRank winnerRank;
  final HandRank loserRank;
  final bool allIn;
  final bool suckout;
  final bool reachedRiver;

  /// Exact head-to-head equity at the moment the money actually went in,
  /// keyed by playerId, for every contender who was all-in before showdown.
  /// Null when nobody was ever all-in pre-showdown — there is no "equity when
  /// all-in" for a hand that was never at risk.
  final Map<String, double>? equityWhenAllIn;

  /// Bart's closing take on the hand as a whole.
  final List<String> commentary;

  /// One line per player who saw the flop.
  final List<PlayerVerdict> verdicts;

  /// Pot in big blinds.
  double get potBb => bigBlind <= 0 ? 0 : pot / bigBlind;

  ReplaySeat? seatOf(String playerId) =>
      seats.where((s) => s.playerId == playerId).firstOrNull;

  HandReplay copyWith({
    List<ReplayStreet>? streets,
    String? headline,
    List<String>? commentary,
    List<PlayerVerdict>? verdicts,
  }) => HandReplay(
    pot: pot,
    bigBlind: bigBlind,
    board: board,
    seats: seats,
    streets: streets ?? this.streets,
    winnerName: winnerName,
    winnerHand: winnerHand,
    loserName: loserName,
    loserHand: loserHand,
    winnerRank: winnerRank,
    loserRank: loserRank,
    allIn: allIn,
    suckout: suckout,
    reachedRiver: reachedRiver,
    equityWhenAllIn: equityWhenAllIn,
    headline: headline ?? this.headline,
    commentary: commentary ?? this.commentary,
    verdicts: verdicts ?? this.verdicts,
  );
}
