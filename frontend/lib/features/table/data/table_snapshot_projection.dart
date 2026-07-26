import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/features/table/domain/table_snapshot.dart';

/// Projects a live [PokerGame] into the flat, serializable [TableSnapshot] the UI
/// renders. Shared by the cash-game [LocalGameRepository] and the tournament
/// live-table facade so both broadcast identical seat/board/action state.
///
/// - [revealAll]: show every hole (all-bots / spectator); otherwise only the
///   human, and everyone still in at showdown.
/// - [behaviorLabels]: per-seat brain/style badge (id -> label), or empty.
/// - [flagBusted]: when true, list any 0-stack seats once the hand is over (the
///   human-vs-bots reload/eliminate prompt); all-bots/eval never busts.
TableSnapshot projectTableSnapshot(
  PokerGame game, {
  bool revealAll = false,
  Map<String, String?> behaviorLabels = const {},
  bool flagBusted = false,
}) {
  final showdownHappened = game.results.any((r) => r.handValue != null);
  final wonByPlayer = {for (final r in game.results) r.player: r.netWon};
  final chopByPlayer = {for (final r in game.results) r.player: r.isSplit};
  final current = game.currentPlayer;

  final seats = <SeatView>[];
  for (var i = 0; i < game.players.length; i++) {
    final p = game.players[i];
    final reveal = p.isHuman || revealAll || (showdownHappened && p.inHand);
    String? label;
    if (reveal && p.inHand && game.board.length == 5 && p.hole.length == 2) {
      label = HandEvaluator.evaluate([...p.hole, ...game.board]).rank.label;
    }
    seats.add(
      SeatView(
        id: p.id,
        name: p.name,
        isHuman: p.isHuman,
        stack: p.stack,
        currentBet: p.currentBet,
        folded: p.hasFolded,
        allIn: p.isAllIn,
        isButton: i == game.buttonIndex,
        isCurrent: current != null && current.id == p.id,
        raiseLevel: p.betLevel,
        wagerIsCall: p.wagerIsCall,
        holeCards: reveal ? List.of(p.hole) : null,
        handLabel: label,
        wonAmount: wonByPlayer[p] ?? 0,
        wonIsChop: chopByPlayer[p] ?? false,
        behavior: behaviorLabels[p.id],
      ),
    );
  }

  ActionContext? ctx;
  if (current != null && current.isHuman) {
    ctx = ActionContext(
      callAmount: game.callAmount(current),
      canCheck: game.canCheck(current),
      minRaiseTo: game.minRaiseTo(current),
      maxRaiseTo: game.maxRaiseTo(current),
      bigBlind: game.bigBlind,
      currentBet: game.currentBet,
      raiseCount: game.raiseCountThisRound,
    );
  }

  final busted = <String>[];
  if (flagBusted && game.isHandOver) {
    for (final p in game.players) {
      if (p.stack == 0) busted.add(p.id);
    }
  }

  return TableSnapshot(
    seats: seats,
    board: List.of(game.board),
    pot: game.pot,
    round: game.round,
    currentPlayerId: current?.id,
    isHandOver: game.isHandOver,
    handInProgress: !game.isHandOver,
    log: List.of(game.log),
    actionContext: ctx,
    bustedPlayerIds: busted,
  );
}
