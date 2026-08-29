import 'package:monte/core/domain/ai/player_kind.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/game.dart';

/// Public + private view of one seat, as the UI needs it.
///
/// This is deliberately a flat, serializable-shaped value: it mirrors what a
/// server would broadcast per player, so moving to client/server later means
/// producing the same snapshot from socket messages instead of the local
/// engine.
class SeatView {
  const SeatView({
    required this.id,
    required this.name,
    required this.isHuman,
    required this.stack,
    required this.currentBet,
    required this.folded,
    required this.allIn,
    required this.isButton,
    required this.isCurrent,
    this.raiseLevel = 0,
    this.wagerIsCall = false,
    this.vpip = false,
    this.raisedPreflop = false,
    this.preflopRaiseLevel = 0,
    this.raisedPostflop = false,
    this.holeCards,
    this.handLabel,
    this.wonAmount = 0,
    this.wonNet = 0,
    this.wonIsChop = false,
    this.behavior,
    this.kind,
    this.generated = false,
    this.actionReason,
  });

  final String id;
  final String name;
  final bool isHuman;
  final int stack;
  final int currentBet;
  final bool folded;
  final bool allIn;
  final bool isButton;
  final bool isCurrent;

  /// The raise level of this seat's current wager: 1 = bet/open, 2 = 3-bet,
  /// 3+ = 4-bet or higher (0 = no raise — a check/limp/blind). Drives the
  /// escalating bet-indicator colour.
  final int raiseLevel;

  /// Whether the current wager came from a call (vs a bet/raise) — picks the
  /// "CALL" vs "BET" label on the indicator.
  final bool wagerIsCall;

  /// This-hand action summary, for reading the seat's likely range: voluntarily
  /// entered the pot preflop, made a preflop raise, and made a postflop raise.
  final bool vpip;
  final bool raisedPreflop;

  /// Preflop raise escalation: 0 none, 1 open, 2 3-bet, 3+ 4-bet.
  final int preflopRaiseLevel;
  final bool raisedPostflop;

  /// Visible only for the local player, or for everyone at showdown.
  final List<Card>? holeCards;

  /// Set at showdown, e.g. "Full House".
  final String? handLabel;

  /// Chips *won from opponents* in the just-completed hand (for a highlight).
  /// Excludes a returned uncalled bet, so a player who only got their own
  /// over-bet back shows nothing.
  final int wonAmount;

  /// What the seat actually **made** on the hand: chips collected less chips
  /// contributed — the change in their stack. [wonAmount] is mostly the
  /// player's own money coming back, so this is the figure worth showing them.
  /// Zero or negative is possible (a chop, or a side pot won while losing the
  /// main), which [wonAmount] can never express.
  final int wonNet;

  /// Whether [wonAmount] was a split pot (a chop) — labels the tag "CHOP".
  final bool wonIsChop;

  /// The bot's behavior model label (brain + style), e.g. "Maniac · MCTS".
  /// Null for the human seat. Shown on the seat only when the player enables it.
  final String? behavior;

  /// Whether this seat is the human, a pro-calibre personality, or a
  /// recreational one — drives the seat's colour coding. Null when the seat's
  /// class isn't known (an untracked bot), which renders untinted.
  final PlayerKind? kind;

  /// True for an anonymous auto-filled tournament seat rather than an
  /// explicitly-chosen personality. Filler gets a softer tint so the players
  /// you actually picked stand out.
  final bool generated;

  /// Human-readable label for the last action this seat took: "call", "bluff",
  /// "tight fold", etc. Communicates what personality trait or heuristic drove
  /// the decision. Null when no action has been recorded or the label is empty.
  final String? actionReason;
}

/// What the human can legally do right now. Null unless it's their turn.
class ActionContext {
  const ActionContext({
    required this.callAmount,
    required this.canCheck,
    required this.minRaiseTo,
    required this.maxRaiseTo,
    required this.bigBlind,
    required this.currentBet,
    this.raiseCount = 0,
    this.chipUnit = 1,
  });

  final int callAmount;
  final bool canCheck;
  final int minRaiseTo;
  final int maxRaiseTo;
  final int bigBlind;
  final int currentBet;

  /// Voluntary bets/raises so far this street: 0 unraised, 1 open, 2 3-bet,
  /// 3+ 4-bet. Lets the coach infer how tight the opponents' range should be.
  final int raiseCount;

  /// The smallest physical chip in play. Every wager must be a whole number of
  /// these, so the slider and the pot-fraction presets snap to it — at a
  /// 100/100 level a "third pot" bet is 100, not 33.
  final int chipUnit;

  /// Snaps a raise target to a legal, chip-aligned amount.
  ///
  /// Rounds to the nearest whole chip and clamps into
  /// `[minRaiseTo, maxRaiseTo]`. Going all-in stays exact even when the stack
  /// isn't a clean multiple, matching the engine's own rule — otherwise the UI
  /// would refuse to let a player shove an odd stack.
  int snapRaise(num target) {
    final max = maxRaiseTo;
    if (target >= max) return max;
    final unit = chipUnit <= 1 ? 1 : chipUnit;
    final snapped = (target / unit).round() * unit;
    // Round *up* to the minimum: a rounded-down value would be an illegal raise.
    if (snapped < minRaiseTo) {
      final up = (minRaiseTo / unit).ceil() * unit;
      return up.clamp(minRaiseTo, max);
    }
    return snapped.clamp(minRaiseTo, max);
  }

  /// The number of distinct chip-aligned raise amounts available — the slider's
  /// division count, so dragging lands on legal values only.
  int get raiseSteps {
    final unit = chipUnit <= 1 ? 1 : chipUnit;
    final span = maxRaiseTo - minRaiseTo;
    if (span <= 0) return 1;
    return (span / unit).ceil().clamp(1, 1 << 20);
  }

  bool get canRaise => maxRaiseTo > currentBet && maxRaiseTo > callAmount;
}

/// An immutable snapshot of the whole table for one render.
class TableSnapshot {
  const TableSnapshot({
    required this.seats,
    required this.board,
    required this.pot,
    required this.round,
    required this.currentPlayerId,
    required this.isHandOver,
    required this.handInProgress,
    required this.log,
    this.actionContext,
    this.bustedPlayerIds = const [],
    this.chipUnit = 1,
    this.denominations = const [1, 5, 25, 100, 500, 1000, 5000, 25000],
  });

  final List<SeatView> seats;
  final List<Card> board;
  final int pot;

  /// The smallest physical chip on the table. Seats never draw a chip smaller
  /// than this — at a 100/100 level there are no 25s in play.
  final int chipUnit;

  /// The denominations available, ascending, for drawing chip stacks.
  final List<int> denominations;
  final BettingRound round;
  final String? currentPlayerId;
  final bool isHandOver;
  final bool handInProgress;
  final List<String> log;

  /// Present only when the local human is on action.
  final ActionContext? actionContext;

  /// Seat ids that have busted (zero chips at the end of a hand) and need the
  /// player's attention — reload their bankroll or seat a new opponent. Only
  /// populated between hands in human-vs-bots play.
  final List<String> bustedPlayerIds;

  bool get isHumanTurn => actionContext != null;

  SeatView? get human => seats
      .where((s) => s.isHuman)
      .cast<SeatView?>()
      .firstWhere((s) => true, orElse: () => null);

  /// An empty pre-game snapshot.
  static const empty = TableSnapshot(
    seats: [],
    board: [],
    pot: 0,
    round: BettingRound.handComplete,
    currentPlayerId: null,
    isHandOver: true,
    handInProgress: false,
    log: [],
  );
}
