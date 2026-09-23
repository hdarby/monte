import 'package:monte/core/domain/ai/preflop_ranges.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/board_texture.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/game.dart' show BettingRound;
import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/core/domain/engine/hand_strength.dart';
import 'package:monte/core/util/format.dart';
import 'package:monte/features/tournament/domain/chronicle/hand_replay.dart';

part 'hand_narrator_signature_moves.dart';
part 'hand_narrator_streets.dart';
part 'hand_narrator_aggression.dart';
part 'hand_narrator_summary.dart';
part 'hand_narrator_context.dart';

/// Generates Bart-Hanson-style commentary over a completed [HandReplay]: a full
/// read on every street, then a closing take with a verdict on each player.
///
/// It is a *commentator*, not a solver. It works from facts the replay already
/// carries — hole cards, board, exact action, positions, stack depths, and each
/// player's style — and applies standard strategic reasoning: board texture,
/// range and nut advantage, pot odds, stack-to-pot ratio, exact outs, fold
/// equity, and whether a bluff had a story behind it.
///
/// Because it can see every hand, it talks like TV commentary: it will call out
/// a loose preflop entry the player themselves could not have known was bad, and
/// it counts a drawing player's outs exactly rather than guessing.
///
/// Deliberately verbose — this is a training tool, so it would rather say one
/// thing too many than leave a spot unexplained.
///
/// Pure and deterministic: same replay in, same words out. No Flutter, no I/O.
///
/// The implementation is split across sibling `part` files (signature moves,
/// per-street narration, aggression/bluff evaluation, closing summary and
/// verdicts, and `_HandContext`/`_Voice`) because everything shares
/// library-private helpers and state; this file keeps only the public entry
/// point.
class HandNarrator {
  const HandNarrator._();

  /// Returns [replay] with per-street commentary, a closing take, one
  /// verdict per player who saw the flop, and a strategic headline.
  static HandReplay narrate(HandReplay replay) {
    final ctx = _HandContext(replay);
    final streets = [
      for (final s in replay.streets)
        s.withCommentary([..._signatureMoves(ctx, s), ..._forStreet(ctx, s)]),
    ];
    return replay.copyWith(
      streets: streets,
      headline: _generateHeadline(replay),
      commentary: _summary(ctx),
      verdicts: _verdicts(ctx),
    );
  }
}

/// Generates a strategic headline describing the key theme of the hand.
String _generateHeadline(HandReplay replay) {
  // Multiway pot with multiple strong holdings
  if (replay.seats.length > 2) {
    return 'Multiway — multiple strong hands in play';
  }

  // Heads-up suckout: winner catches on river despite being behind
  if (replay.suckout && replay.reachedRiver) {
    return 'River suckout — ${replay.winnerName} hits from behind';
  }

  // All-in confrontation: heads-up at-risk situation
  if (replay.allIn) {
    return 'All-in collision — ${replay.winnerName} vs ${replay.loserName}';
  }

  // Trap/deception: winner had worse hand ranking but won anyway
  if (replay.loserRank.index > replay.winnerRank.index && !replay.allIn) {
    return 'Trap played out — ${replay.winnerName} was behind but had the plan';
  }

  // Default: straightforward hand with best hand holding up
  return '${replay.winnerName} takes it with ${replay.winnerHand.toLowerCase()}';
}

List<String> _forStreet(_HandContext ctx, ReplayStreet street) {
  // A postflop street with no betting means the money was already in and the
  // board is simply running out. It is still worth narrating — that runout
  // decided the hand — but none of the decision commentary applies, and the
  // flop writer would otherwise call an all-in board "checked through".
  if (street.round != BettingRound.preflop &&
      street.actions.isEmpty &&
      ctx.replay.allIn) {
    return _runout(ctx, street);
  }
  return switch (street.round) {
    BettingRound.preflop => _preflop(ctx, street),
    BettingRound.flop => _flop(ctx, street),
    BettingRound.turn => _turn(ctx, street),
    _ => _river(ctx, street),
  };
}

// ---- Small helpers shared across the parts above --------------------------

String _sizingWord(double potFraction) {
  if (potFraction <= 0) return 'a token amount';
  if (potFraction < 0.34) return 'a small stab, about a third of the pot';
  if (potFraction < 0.55) return 'about half pot';
  if (potFraction < 0.8) return 'two-thirds of the pot';
  if (potFraction <= 1.1) return 'a pot-sized bet';
  return 'an overbet';
}

String _names(Iterable<String> names) {
  final list = names.toList();
  if (list.isEmpty) return 'nobody';
  if (list.length == 1) return list.first;
  return '${list.sublist(0, list.length - 1).join(', ')} and ${list.last}';
}

String _join(List<String> parts) {
  if (parts.length == 1) return parts.first;
  return '${parts.sublist(0, parts.length - 1).join('; ')}; and ${parts.last}';
}

/// An equity fraction as a whole-number percentage, for the equity-banded
/// suckout/cooler language.
int _pct(double equity) => (equity * 100).round();
