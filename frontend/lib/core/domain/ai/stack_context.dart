import 'dart:math';

import 'package:meta/meta.dart';

import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

/// How deep the table is, in big blinds. A **preflop** concept: it decides how
/// tight to open, when to 3-bet, and when a hand is worth playing for a stack.
///
/// Measured from the start-of-hand stacks, so it is constant for the whole hand.
/// That matters — see [StackContext.depthBb].
enum StackRegime {
  /// Too shallow to play postflop: raise-or-fold, and a raise means all-in.
  pushFold,

  /// One raise commits a big share of the stack; play straightforward.
  short,

  /// The familiar ~100 BB game everything else is calibrated against.
  normal,

  /// Position, implied odds and pot control start to dominate.
  deep,

  /// Main Event level 1. Pots should stay small and stacks go in rarely.
  veryDeep;

  /// The regime for an effective stack of [bb] big blinds.
  static StackRegime forDepth(double bb) {
    if (bb <= 12) return StackRegime.pushFold;
    if (bb <= 30) return StackRegime.short;
    if (bb <= 100) return StackRegime.normal;
    if (bb <= 250) return StackRegime.deep;
    return StackRegime.veryDeep;
  }
}

/// Stack-to-pot ratio bands — the **postflop** counterpart to [StackRegime].
///
/// SPR, not stack depth, is what decides whether a hand can be played for
/// stacks: at SPR 1 top pair is a happy stack-off, at SPR 13 it is a hand to
/// keep the pot small with. The classic bands.
enum SprBand {
  /// Already pot-committed; the rest is going in.
  committed,

  /// Top pair / overpair territory — one pair is enough to play for it.
  low,

  /// Two pair or a big draw before stacks go in.
  medium,

  /// Needs a genuinely strong hand to build toward a stack-off.
  high,

  /// Only the near-nuts should be trying to get stacks in.
  veryHigh;

  static SprBand forSpr(double spr) {
    if (spr <= 1) return SprBand.committed;
    if (spr <= 3) return SprBand.low;
    if (spr <= 6) return SprBand.medium;
    if (spr <= 13) return SprBand.high;
    return SprBand.veryHigh;
  }
}

/// The one place stack depth and stack-to-pot ratio are computed.
///
/// This used to be a lone `deepFactor` scalar, recomputed independently inside
/// three different policies — and each copy had the same bug, because each read
/// depth off the player's *remaining* stack. That made the depth estimate
/// collapse as chips went in, so the deep-stack discipline switched itself off
/// exactly when a pot was bloating (worst preflop, where a 4-bet war left a bot
/// believing it was short and shipping 300 BB with QQ). Computing it once, from
/// the start-of-hand stacks, is what stops that recurring.
///
/// The two numbers answer different questions and both are needed:
///
/// - [depthBb] / [regime] — "how deep is this game?" Constant through the hand;
///   drives preflop ranges and how willing anyone is to play for a stack.
/// - [spr] / [sprBand] — "can this hand still play for stacks?" **Falls** as the
///   pot grows, which is the point: pot bloat *is* SPR crashing from 40 to 3
///   over three streets.
@immutable
class StackContext {
  const StackContext({
    required this.effectiveStart,
    required this.behind,
    required this.pot,
    required this.bigBlind,
    required this.streetsRemaining,
  });

  /// Effective stack at the *start of the hand* (hero vs the deepest live
  /// opponent), in chips.
  final int effectiveStart;

  /// Effective chips still behind right now — what a stack-off would risk.
  final int behind;

  /// The pot as it stands.
  final int pot;

  final int bigBlind;

  /// Betting rounds still to come after this one (flop → 2, river → 0). Used by
  /// [geometricFraction] to size a hand toward a stack-off.
  final int streetsRemaining;

  /// Reads the context for [p] in [game].
  factory StackContext.of(PokerGame game, Player p) {
    final live =
        game.players.where((x) => x.inHand && !identical(x, p)).toList();
    int start(Player x) => x.totalContributed + x.stack;
    final deepestStart =
        live.isEmpty ? start(p) : live.map(start).reduce(max);
    final deepestBehind = live.isEmpty ? p.stack : live.map((x) => x.stack).reduce(max);
    return StackContext(
      effectiveStart: min(start(p), deepestStart),
      behind: min(p.stack, deepestBehind),
      pot: game.pot,
      bigBlind: game.bigBlind,
      streetsRemaining: switch (game.round) {
        BettingRound.preflop => 3,
        BettingRound.flop => 2,
        BettingRound.turn => 1,
        _ => 0,
      },
    );
  }

  /// Effective stack in big blinds, from the start-of-hand stacks.
  double get depthBb => bigBlind <= 0 ? 100 : effectiveStart / bigBlind;

  StackRegime get regime => StackRegime.forDepth(depthBb);

  /// Stack-to-pot ratio: chips still behind, over the current pot.
  double get spr => pot <= 0 ? double.infinity : behind / pot;

  SprBand get sprBand => SprBand.forSpr(spr);

  /// A 0–1 ramp of "how deep are we beyond a normal stack": 0 at ≤100 BB,
  /// reaching 1 by ~300 BB.
  ///
  /// Kept because every existing threshold in the policies is tuned against this
  /// exact curve; [regime] is the expressive form for new decisions.
  double get depthPressure => ((depthBb - 100.0) / 200.0).clamp(0.0, 1.0);

  /// The constant pot fraction that gets [behind] all-in over the remaining
  /// betting rounds, if every bet is called.
  ///
  /// Betting `f · pot` and being called multiplies the pot by `(1 + 2f)`, so
  /// over `n` streets the total wagered is `pot · ((1+2f)^n − 1) / 2`. Setting
  /// that equal to the stack gives `f = ((1 + 2·spr)^(1/n) − 1) / 2`.
  ///
  /// This is the *deliberate* stack-off size — right with a monster, and
  /// enormous when deep (at SPR 40 it asks for a 1.7× pot overbet, which is
  /// exactly why you cannot get 300 BB in with one pair). [potControlFraction]
  /// is the other half of the choice.
  double geometricFraction([int? streets]) {
    final n = (streets ?? streetsRemaining).clamp(1, 4);
    final s = spr;
    if (!s.isFinite || s <= 0) return 1.0;
    return (pow(1 + 2 * s, 1 / n) - 1) / 2;
  }

  /// The constant pot fraction that **arrives at** an SPR of [targetSpr] by the
  /// end of the hand, betting and being called on every remaining street.
  ///
  /// This is the sizing decision a good deep-stacked player actually makes: pick
  /// the stack-to-pot ratio you want to be facing when the money goes in, then
  /// bet the size that gets you there. Near-nuts wants `targetSpr` 0 (a
  /// stack-off, i.e. [geometricFraction]); one pair 300 BB deep wants a high
  /// target, which forces a small bet.
  ///
  /// Betting `f` for `n` streets multiplies the pot by `R = (1+2f)^n` and puts
  /// `pot·(R−1)/2` in, so the final SPR is `(spr − (R−1)/2) / R`. Setting that
  /// to [targetSpr] gives `R = (spr + ½) / (targetSpr + ½)`.
  ///
  /// Note this is *not* the same as [potControlFraction], which only looks one
  /// street ahead and so barely constrains a deep stack — at SPR 40 it happily
  /// allows a 2.6× pot bet. Looking all the way to the river is what turns
  /// "keep the pot small" into an actual number.
  double fractionToReachSpr(double targetSpr, [int? streets]) {
    final n = (streets ?? streetsRemaining).clamp(1, 4);
    final s = spr;
    if (!s.isFinite) return 3.0;
    final r = (s + 0.5) / (targetSpr.clamp(0.0, 1e6) + 0.5);
    if (r <= 1) return 0.0; // already at or past the target — check
    return ((pow(r, 1 / n) - 1) / 2).clamp(0.0, 3.0);
  }

  /// The largest bet that still leaves the SPR above [floor] once called — the
  /// size to choose when the hand is *not* worth playing for stacks.
  ///
  /// Solving `behind − f·pot ≥ floor · pot · (1 + 2f)` for `f`. Returns 0 when
  /// even a minimum bet would breach the floor, i.e. "just check".
  double potControlFraction(double floor) {
    if (pot <= 0 || floor <= 0) return 1.0;
    final f = (spr - floor) / (1 + 2 * floor);
    return f.isFinite ? f.clamp(0.0, 3.0) : 3.0;
  }

  @override
  String toString() => 'StackContext(${depthBb.toStringAsFixed(0)}bb '
      '${regime.name}, spr=${spr.isFinite ? spr.toStringAsFixed(1) : "inf"} '
      '${sprBand.name})';
}
