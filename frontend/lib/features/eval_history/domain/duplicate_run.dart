import 'dart:math';

import 'package:meta/meta.dart';

import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';

/// Replays logged hands with somebody else in the player's seat.
///
/// This is the one measurement in the review that does not rest on a model. The
/// coach's expected-value figures are a heuristic — a 40% range assumption and a
/// few hundred Monte-Carlo runouts — and when it says a decision cost twelve big
/// blinds you are trusting an approximation of poker. Here the same cards are
/// dealt to the same opponents with a different player in the chair, and if the
/// substitute makes more money then it made more money. Nothing in between to be
/// wrong about.
///
/// It benchmarks the bots as much as the human: a substitute who cannot beat the
/// player is either facing good play or is not as strong as advertised, and both
/// are worth knowing.
///
/// **It is a duplicate, not a counterfactual.** Once the substitute deviates the
/// hand diverges, because the opponents respond to *their* action and not to the
/// one that was actually taken. That is precisely how duplicate poker events
/// work and it is meaningful for the same reason, but the claim is "same cards,
/// same opponents, different player" — never "this is what would have happened".
class DuplicateRun {
  const DuplicateRun._();

  /// Replays [hand] [runs] times with [substitute] in [seatId]'s chair.
  ///
  /// Returns the substitute's average net in big blinds, or null when the hand
  /// cannot be reconstructed (a seat with no cards recorded, too few players).
  static double? replay(
    EvalHand hand,
    String seatId, {
    required DecisionPolicy Function(String seatId) deciderFor,
    required DecisionPolicy substitute,
    int runs = 200,
    int seed = 0,
  }) {
    final seats = hand.players;
    if (seats.length < 2) return null;
    if (seats.any((p) => p.holeCards.length != 2)) return null;
    final hero = seats.where((p) => p.id == seatId).firstOrNull;
    if (hero == null) return null;
    final bb = hand.bigBlind <= 0 ? 1 : hand.bigBlind;

    var total = 0.0;
    var counted = 0;
    for (var i = 0; i < runs; i++) {
      final net = _once(hand, seatId, deciderFor, substitute, seed + i);
      if (net == null) continue;
      total += net / bb;
      counted++;
    }
    return counted == 0 ? null : total / counted;
  }

  /// One replay. Returns the substitute's chip net, or null if unreconstructable.
  static int? _once(
    EvalHand hand,
    String seatId,
    DecisionPolicy Function(String) deciderFor,
    DecisionPolicy substitute,
    int seed,
  ) {
    final seats = hand.players;
    final n = seats.length;

    // Seat everyone in button order, so `seatsFromButton` reproduces the real
    // positions and the blinds land on the same players.
    final ordered = [...seats]
      ..sort((a, b) => a.seatsFromButton.compareTo(b.seatsFromButton));
    final players = [
      for (final s in ordered)
        Player(
          id: s.id,
          name: s.name,
          stack: s.startingStack,
          isHuman: false, // every seat is bot-driven in a replay
        ),
    ];

    // `startHand` deals two rounds round-robin from the top of the deck, so
    // seat i takes indices i and n+i. The board follows, one burn before the
    // flop and one before each later card.
    final order = List<Card?>.filled(52, null);
    for (var i = 0; i < n; i++) {
      order[i] = Card.fromCode(ordered[i].holeCards[0]);
      order[n + i] = Card.fromCode(ordered[i].holeCards[1]);
    }
    final board = [for (final c in hand.board) Card.fromCode(c)];
    var at = 2 * n;
    for (var i = 0; i < board.length; i++) {
      if (i == 0 || i >= 3) at++; // burn before the flop, turn and river
      order[at++] = board[i];
    }

    // Fill the gaps with whatever is left, shuffled per run so the cards still
    // to come vary when the replay runs past the recorded board.
    final used = order.whereType<Card>().toSet();
    final rest = [
      for (final s in Suit.values)
        for (final r in Rank.values)
          if (!used.contains(Card(r, s))) Card(r, s),
    ]..shuffle(Random(seed));
    var k = 0;
    final deck = [for (final c in order) c ?? rest[k++]];

    final game = PokerGame(
      players: players,
      smallBlind: hand.smallBlind,
      bigBlind: hand.bigBlind,
      ante: hand.ante,
      deck: Deck.stacked(deck),
      rotateButton: false,
    )..buttonIndex = 0; // ordered[0] is the button by construction

    game.startHand();
    if (game.isHandOver) return null;

    final before = players.firstWhere((p) => p.id == seatId).stack;
    var guard = 0;
    while (!game.isHandOver && guard++ < 400) {
      final p = game.currentPlayer;
      if (p == null) break;
      final policy = p.id == seatId ? substitute : deciderFor(p.id);
      GameAction action;
      try {
        action = policy.decide(game, p);
      } catch (_) {
        // A policy that throws must not abort the whole run; fold it out.
        action = game.canCheck(p)
            ? const GameAction.check()
            : const GameAction.fold();
      }
      game.applyAction(action);
    }
    if (!game.isHandOver) return null;
    // `startHand` already took the blinds and ante out of the stack, so the
    // comparison has to be against the seat's stack *after* posting, not its
    // starting stack — otherwise every hand looks like it lost the blind.
    final hero = players.firstWhere((p) => p.id == seatId);
    return hero.stack - before;
  }
}

/// One hand's duplicate result.
@immutable
class DuplicateHand {
  const DuplicateHand({
    required this.hand,
    required this.yoursBb,
    required this.theirsBb,
  });

  final EvalHand hand;

  /// What the player actually made, and what the substitute averaged.
  final double yoursBb;
  final double theirsBb;

  double get gapBb => theirsBb - yoursBb;
}

/// A whole session replayed.
@immutable
class DuplicateReport {
  const DuplicateReport({
    required this.substituteName,
    required this.hands,
    required this.runsPerHand,
  });

  final String substituteName;
  final List<DuplicateHand> hands;
  final int runsPerHand;

  double get yoursBb => hands.fold(0.0, (a, h) => a + h.yoursBb);
  double get theirsBb => hands.fold(0.0, (a, h) => a + h.theirsBb);
  double get gapBb => theirsBb - yoursBb;

  /// The hands where the substitute gained most, worst first.
  List<DuplicateHand> get biggestGaps =>
      [...hands]..sort((a, b) => b.gapBb.compareTo(a.gapBb));
}
