import '../engine/card.dart';
import '../engine/game.dart';

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
    this.holeCards,
    this.handLabel,
    this.wonAmount = 0,
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

  /// Visible only for the local player, or for everyone at showdown.
  final List<Card>? holeCards;

  /// Set at showdown, e.g. "Full House".
  final String? handLabel;

  /// Chips won in the just-completed hand (for a highlight).
  final int wonAmount;
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
  });

  final int callAmount;
  final bool canCheck;
  final int minRaiseTo;
  final int maxRaiseTo;
  final int bigBlind;
  final int currentBet;

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
  });

  final List<SeatView> seats;
  final List<Card> board;
  final int pot;
  final BettingRound round;
  final String? currentPlayerId;
  final bool isHandOver;
  final bool handInProgress;
  final List<String> log;

  /// Present only when the local human is on action.
  final ActionContext? actionContext;

  bool get isHumanTurn => actionContext != null;

  SeatView? get human =>
      seats.where((s) => s.isHuman).cast<SeatView?>().firstWhere(
            (s) => true,
            orElse: () => null,
          );

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
