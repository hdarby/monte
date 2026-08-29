import 'package:monte/core/domain/ai/player_kind.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
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
/// - [seatProfiles]: per-seat personality (id -> profile), used to colour the
///   seat pro vs recreational. Seats absent from the map render untinted.
/// - [flagBusted]: when true, list any 0-stack seats once the hand is over (the
///   human-vs-bots reload/eliminate prompt); all-bots/eval never busts.
TableSnapshot projectTableSnapshot(
  PokerGame game, {
  bool revealAll = false,
  Map<String, String?> behaviorLabels = const {},
  Map<String, PlayerProfile> seatProfiles = const {},
  bool flagBusted = false,
  String? frontPlayerId,
  List<int>? denominations,
  Map<String, String?> actionReasons = const {},
}) {
  final showdownHappened = game.results.any((r) => r.handValue != null);
  final wonByPlayer = {for (final r in game.results) r.player: r.netWon};
  final netByPlayer = {for (final r in game.results) r.player: r.netGain};
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
        vpip: p.vpip,
        raisedPreflop: p.raisedPreflop,
        preflopRaiseLevel: p.preflopRaiseLevel,
        raisedPostflop: p.raisedPostflop,
        holeCards: reveal ? List.of(p.hole) : null,
        handLabel: label,
        wonAmount: wonByPlayer[p] ?? 0,
        wonNet: netByPlayer[p] ?? 0,
        wonIsChop: chopByPlayer[p] ?? false,
        behavior: behaviorLabels[p.id],
        kind: PlayerKind.of(seatProfiles[p.id], isHuman: p.isHuman),
        generated: seatProfiles[p.id]?.generated ?? false,
        actionReason: actionReasons[p.id],
      ),
    );
  }

  // Rotate the seat ring so [frontPlayerId] sits first — the UI renders index 0
  // at bottom-centre, so this keeps the human (in a tournament, wherever they've
  // been reseated) anchored at the bottom with the rest fanned around them. The
  // dealer button travels with its seat, so it simply moves as expected.
  if (frontPlayerId != null) {
    final k = seats.indexWhere((s) => s.id == frontPlayerId);
    if (k > 0) {
      final rotated = [...seats.sublist(k), ...seats.sublist(0, k)];
      seats
        ..clear()
        ..addAll(rotated);
    }
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
      chipUnit: game.chipUnit,
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
    chipUnit: game.chipUnit,
    denominations: denominations ?? _defaultDenominations,
  );
}

/// Cash-game chip ladder, used when no tournament chip set is supplied.
const _defaultDenominations = [1, 5, 25, 100, 500, 1000, 5000, 25000];
