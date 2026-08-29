import 'dart:math';

import 'package:monte/core/domain/ai/action_candidate.dart';
import 'package:monte/core/domain/ai/mental_state.dart';
import 'package:monte/core/domain/ai/personality_post_processor.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/stack_context.dart';
import 'package:monte/core/domain/ai/trigger_context.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/bet_sizing.dart';
import 'package:monte/core/domain/engine/board_texture.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/core/domain/engine/player.dart';

/// The postflop poker judgement itself, factored out of
/// `ProfilePostflopPolicy.decide()` so the threshold-shifting inputs (read-
/// derived exploit terms, personality, tilt) stay owned by the policy while
/// the branch logic — value/bluff/check-raise/trap plans, sizing, and the
/// commitment gates — lives in one place.
///
/// This class makes **no** decision about *why* a threshold moved (that is
/// the caller's job, computed once in `ProfilePostflopPolicy.decide()` and
/// passed in as plain numbers); it only plays the hand given those numbers,
/// exactly as `ProfilePostflopPolicy` used to inline it. Random rolls happen
/// in the same order as before — [random] must be the policy's shared,
/// seeded instance, or determinism tests break.
class HeuristicPostflopEvaluator {
  HeuristicPostflopEvaluator(this._random);

  final Random _random;

  /// Plays the hand given a bet to call (or none) and every threshold input
  /// the policy has already derived. Returns the `chosen` [ActionCandidate]
  /// plus, at the two genuine two-live-candidate decision points (call vs.
  /// fold near `callBar`; bet vs. check near the value/bluff threshold), the
  /// `runnerUp` the hard-cutoff logic rejected — for
  /// `PersonalityPostProcessor.mix` to consider. `runnerUp.margin` is always
  /// `0`, the reference "exactly on the bar" point, so `mix`'s gap collapses
  /// to `chosen.margin.abs()`: how far this hand actually sits from its own
  /// threshold. Every other return (commitment-gated, probabilistic float/
  /// trap/hero-call lines) has no well-defined alternative to mix against and
  /// leaves `runnerUp` null. The caller (policy) is responsible for calling
  /// `mix`, then firing [PersonalityPostProcessor.fireTriggers] on whichever
  /// candidate survives and returning its `.action`.
  ({ActionCandidate chosen, ActionCandidate? runnerUp}) decide({
    required PokerGame game,
    required Player p,
    required PlayerProfile profile,
    required StackContext ctx,
    required TriggerContext tc,
    required MentalReads? mental,
    required double eq,
    required bool isDraw,
    required BoardTexture? texture,
    required double pv,
    required double sr,
    required double geoBoost,
    required double checkRaiseProf,
    required double exploit,
    required double sizeScale,
    required double deepFactor,
    required double rValueThin,
    required double rBluffMore,
    required double rSuspect,
    required int liveOpp,
    required int toCall,
    required int bb,
    required bool canRaise,
    required double betFraction,
    required bool inPosition,
  }) {
    GameAction betBy(double fraction) =>
        GameAction.bet(potBetTo(game, p, fraction));

    GameAction raiseBy(double fraction) =>
        GameAction.raise(potRaiseTo(game, p, fraction));

    ({ActionCandidate chosen, ActionCandidate? runnerUp}) only(
      ActionCandidate c,
    ) =>
        (chosen: c, runnerUp: null);

    // No bet to face: value-bet (exploit bets thinner) or bluff (exploit and
    // draws bluff more; GTO still bluffs a small balanced amount).
    if (toCall == 0) {
      final wantsValue = eq >
          0.60 - 0.10 * exploit - 0.10 * pv - 0.08 * sr + 0.10 * deepFactor -
              rValueThin;
      final mood = mental?.stateFor(p.id);
      final tiltBluff = mood == null || !mood.isTilted
          ? 1.0
          : (1 +
                  0.9 * mood.tiltPressure * profile.proficiencyOf('Tilt_Blowup') -
                  0.7 * mood.tiltPressure *
                      profile.proficiencyOf('Tilt_Shutdown'))
              .clamp(0.1, 2.5);
      final bluffChance = tiltBluff *
          ((0.10 + 0.35 * exploit + 0.30 * pv + 0.30 * sr) *
                      ((1 - eq) * 0.6 + (isDraw ? 0.4 : 0.0)) +
                  0.4 * rBluffMore) *
              (1 - 0.45 * deepFactor);
      final wantsBluff = _random.nextDouble() < bluffChance;

      final float = profile.proficiencyOf('Float_And_Take_Away');
      if (float > 0 &&
          tc.onTurn &&
          tc.calledFlop &&
          tc.inPosition &&
          tc.headsUp &&
          eq < 0.55 &&
          p.stack > bb &&
          _random.nextDouble() < 0.65 * float) {
        final b = betBy((0.55 * sizeScale).clamp(0.33, 0.75));
        final risked = b.amount - p.currentBet;
        if (_commitOk(p, risked, eq, deepFactor, aggressive: true)) {
          return (
            chosen: ActionCandidate(b, label: 'floatTakeAway'),
            runnerUp: null,
          );
        }
      }

      final crPlan = (0.26 + 0.35 * checkRaiseProf) * (1 + 0.4 * exploit);
      if (!inPosition &&
          !tc.onRiver &&
          (eq > 0.70 || isDraw) &&
          p.stack > bb &&
          _random.nextDouble() < crPlan) {
        return (
          chosen:
              ActionCandidate(const GameAction.check(), label: 'checkRaisePlan'),
          runnerUp: null,
        );
      }

      final trap = profile.proficiencyOf('Slow_Play_Trap');
      if (trap > 0 &&
          !tc.onRiver &&
          wantsValue &&
          eq > 0.86 &&
          tc.madeAtLeast(HandRank.threeOfAKind) &&
          _random.nextDouble() < 0.55 * trap) {
        return (
          chosen: ActionCandidate(const GameAction.check(), label: 'slowPlayTrap'),
          runnerUp: null,
        );
      }

      if ((wantsValue || wantsBluff) && p.stack > bb) {
        final sprCap = ctx.fractionToReachSpr(
          _targetSpr(wantsValue ? eq : min(eq, 0.5), ctx.spr),
        );
        final b = betBy(
          _sizeFraction(
            texture: texture,
            polarised: !wantsValue || eq > 0.85,
            thinValue: wantsValue && eq < 0.72,
            opponents: liveOpp,
            sizeScale: sizeScale,
            pressure: pv,
            geoBoost: geoBoost,
            cap: sprCap,
          ),
        );
        final risked = b.amount - p.currentBet;
        if (_commitOk(p, risked, eq, deepFactor, aggressive: true) &&
            _flushCommitOk(game, p, risked, eq)) {
          return (
            chosen: ActionCandidate(
              b,
              label: wantsValue ? 'valueBet' : 'bluffBet',
              margin: wantsValue ? eq - 0.60 : 0.60 - eq,
              meta: {
                'pv': pv,
                'geoBoost': geoBoost,
                'sr': sr,
                'tiltBlowupBluff': wantsBluff &&
                    !wantsValue &&
                    mood != null &&
                    mood.isTilted &&
                    profile.proficiencyOf('Tilt_Blowup') > 0,
              },
            ),
            // The natural counterfactual at this same decision point: a hand
            // sitting exactly on the value/bluff threshold is a genuine
            // coin-flip between betting and checking it back. `margin: 0`
            // marks it as the "exactly on the bar" reference, so `mix`'s gap
            // reduces to how far this hand actually sits from that bar.
            runnerUp: ActionCandidate(const GameAction.check(), label: 'check'),
          );
        }
      }
      return only(ActionCandidate(const GameAction.check(), label: 'check'));
    }

    // Facing a bet.
    final potOdds = toCall / (game.pot + toCall);
    final isCheckRaise = p.checkedThisRound;
    final crEdge = isCheckRaise ? 0.15 + 0.10 * checkRaiseProf : 0.0;
    final wantsValueRaise =
        eq > 0.74 - 0.08 * exploit - 0.10 * pv + 0.12 * deepFactor - crEdge;
    final onRiver = game.round == BettingRound.river;
    final wantsBluffRaise = onRiver
        ? eq < 0.35 &&
            _random.nextDouble() <
                (0.005 + 0.5 * rBluffMore.clamp(0.0, 0.30)).clamp(0.0, 0.10)
        : isDraw &&
            _random.nextDouble() <
                (0.04 +
                        0.22 * exploit +
                        0.22 * pv +
                        (isCheckRaise ? 0.16 + 0.28 * checkRaiseProf : 0.0)) *
                    (1 - 0.55 * deepFactor);
    final wantsCheckRaise = isCheckRaise &&
        (tc.madeAtLeast(HandRank.twoPair) || (isDraw && !tc.onRiver)) &&
        _random.nextDouble() < 0.30 + 0.35 * checkRaiseProf;

    if (canRaise && (wantsValueRaise || wantsBluffRaise || wantsCheckRaise)) {
      final raiseCap = ctx.fractionToReachSpr(
        _targetSpr(wantsValueRaise ? eq : min(eq, 0.5), ctx.spr),
      );
      final r = raiseBy(
        _sizeFraction(
          texture: texture,
          polarised: wantsBluffRaise || eq > 0.85,
          thinValue: wantsValueRaise && eq < 0.80,
          opponents: liveOpp,
          sizeScale: sizeScale,
          pressure: pv,
          geoBoost: geoBoost,
          cap: raiseCap,
        ),
      );
      final risked = r.amount - p.currentBet;
      if (_commitOk(p, risked, eq, deepFactor, aggressive: true) &&
          _flushCommitOk(game, p, risked, eq)) {
        return only(ActionCandidate(
          r,
          label: 'raise',
          meta: {
            'pv': pv,
            'geoBoost': geoBoost,
            'checkRaiseMerchant': isCheckRaise && checkRaiseProf > 0,
          },
        ));
      }
      // Too committing to raise deep without the goods — just continue if priced.
    }

    final riverMargin = onRiver ? 0.02 : 0.0;
    var callBar =
        potOdds + riverMargin + 0.06 * deepFactor * betFraction.clamp(0.0, 1.5);
    final baseBar = callBar;
    final underbluff = profile.proficiencyOf('Underbluff_Exploit');
    if (underbluff > 0 && onRiver && tc.villainIsRecreational) {
      callBar += 0.18 * underbluff;
    }

    final sticky = profile.proficiencyOf('Sticky_Showdown');
    final stickyDelta =
        sticky > 0 && (tc.hasTopPair || tc.madeAtLeast(HandRank.twoPair))
            ? -0.14 * sticky
            : 0.0;
    callBar += stickyDelta;

    final mind = mental?.stateFor(p.id);
    var chaseDelta = 0.0;
    var shutdownDelta = 0.0;
    if (mind != null && mind.isTilted) {
      final t = mind.tiltPressure;
      chaseDelta = -0.16 * t * profile.proficiencyOf('Tilt_Chase');
      shutdownDelta = 0.14 * t * profile.proficiencyOf('Tilt_Shutdown');
      callBar += chaseDelta + shutdownDelta;
    }

    // The comparisons that decide *which* bar-shift traits actually pushed
    // the bar past this hand's equity (not merely held) live in
    // `PersonalityPostProcessor` — this is just the raw data it needs.
    final barShiftMeta = {
      'callBar': callBar,
      'baseBar': baseBar,
      'eq': eq,
      'stickyDelta': stickyDelta,
      'chaseDelta': chaseDelta,
      'shutdownDelta': shutdownDelta,
      'underbluffFires': underbluff > 0 && onRiver && tc.villainIsRecreational,
    };

    if (eq >= callBar &&
        _commitOk(p, toCall, eq, deepFactor) &&
        _flushCommitOk(game, p, toCall, eq)) {
      return (
        chosen: ActionCandidate(
          const GameAction.call(),
          label: 'call',
          margin: eq - callBar,
          meta: barShiftMeta,
        ),
        // Same decision point's natural counterfactual: fold, at the
        // reference "exactly on `callBar`" point (margin 0) — see the bet/
        // check runnerUp above for why.
        runnerUp: ActionCandidate(
          const GameAction.fold(),
          label: 'fold',
          meta: barShiftMeta,
        ),
      );
    }

    final floatProf = profile.proficiencyOf('Float_And_Take_Away');
    if (floatProf > 0 &&
        tc.onFlop &&
        tc.inPosition &&
        tc.headsUp &&
        !tc.madeAtLeast(HandRank.pair) &&
        betFraction <= 0.75 &&
        canRaise &&
        _random.nextDouble() < 0.5 * floatProf &&
        _commitOk(p, toCall, eq, deepFactor)) {
      return only(ActionCandidate(
        const GameAction.call(),
        label: 'floatCall',
        meta: barShiftMeta,
      ));
    }

    final heroCallChance = (0.01 + rSuspect).clamp(0.0, 0.30);
    if (eq >= callBar - 0.05 &&
        _random.nextDouble() < heroCallChance &&
        _commitOk(p, toCall, eq, deepFactor) &&
        _flushCommitOk(game, p, toCall, eq)) {
      return only(ActionCandidate(
        const GameAction.call(),
        label: 'heroCall',
        margin: eq - (callBar - 0.05),
        meta: barShiftMeta,
      ));
    }
    return (
      chosen: ActionCandidate(
        const GameAction.fold(),
        label: 'fold',
        margin: callBar - eq,
        meta: barShiftMeta,
      ),
      // The same call-vs-fold decision point, mirrored: if the hard cutoff
      // landed on fold, call is the runnerUp at the "exactly on callBar"
      // reference point.
      runnerUp: ActionCandidate(
        const GameAction.call(),
        label: 'call',
        meta: barShiftMeta,
      ),
    );
  }

  /// The commitment gate that stops a bot playing a whole stack off on a
  /// pot-odds call. See the original `ProfilePostflopPolicy` docs for the
  /// rationale — unchanged by this move.
  bool _commitOk(
    Player p,
    int risked,
    double equity,
    double deepFactor, {
    bool aggressive = false,
  }) {
    if (risked <= 0) return true;
    final effTotal = p.totalContributed + p.stack;
    if (effTotal <= 0) return true;
    final commitFrac = ((p.totalContributed + risked) / effTotal).clamp(0.0, 1.0);
    if (commitFrac < 0.30) return true;
    final shallow = aggressive ? 0.0 : 0.30 + 0.30 * commitFrac;
    final deep = deepFactor <= 0 ? 0.0 : 0.53 + 0.50 * commitFrac * deepFactor;
    final bar = max(shallow, deep).clamp(0.0, 0.98);
    return equity >= bar;
  }

  /// A disciplined player won't stack off with a non-nut flush into a big pot.
  bool _flushCommitOk(PokerGame game, Player p, int risked, double equity) {
    final sev = _overflushRisk(p.hole, game.board);
    if (sev <= 0) return true;
    final total = p.stack + p.currentBet;
    final commitFrac = total <= 0 ? 1.0 : risked / total;
    if (commitFrac < 0.35) return true;
    final mw = game.players.where((x) => x.inHand && !identical(x, p)).length;
    if (mw < 2 && sev < 0.75) return true;
    final bar = (0.60 + 0.22 * sev + 0.10 * (mw - 1)).clamp(0.0, 0.985);
    return equity >= bar;
  }

  static double _overflushRisk(List<Card> hole, List<Card> board) {
    if (hole.length < 2 || board.length < 3) return 0;
    final all = [...hole, ...board];
    if (HandEvaluator.evaluate(all).rank != HandRank.flush) return 0;
    final counts = <Suit, int>{};
    for (final c in all) {
      counts[c.suit] = (counts[c.suit] ?? 0) + 1;
    }
    final suit = counts.entries.firstWhere((e) => e.value >= 5).key;
    final seen = all
        .where((c) => c.suit == suit)
        .map((c) => c.rank.value)
        .toSet();
    final heroTop = hole
        .where((c) => c.suit == suit)
        .map((c) => c.rank.value)
        .fold(0, max);
    var higherLive = 0;
    for (var r = 14; r > heroTop; r--) {
      if (!seen.contains(r)) higherLive++;
    }
    return (higherLive / 4).clamp(0.0, 1.0);
  }

  static double _targetSpr(double equity, double current) {
    final retain = equity >= 0.88
        ? 0.00
        : equity >= 0.78
            ? 0.10
            : equity >= 0.68
                ? 0.20
                : equity >= 0.58
                    ? 0.35
                    : 0.55;
    if (!current.isFinite) return retain <= 0 ? 0 : 1e6;
    return current * retain;
  }

  double _sizeFraction({
    required BoardTexture? texture,
    required bool polarised,
    required bool thinValue,
    required int opponents,
    required double sizeScale,
    required double pressure,
    required double geoBoost,
    required double cap,
  }) {
    var f = 0.52;

    if (texture != null) {
      if (texture.isStatic) f -= 0.16;
      if (texture.isDynamic) f += 0.16;
      if (texture.isDry) f -= 0.08;
      if (texture.isWet) f += 0.10;
      if (texture.isMonochrome) f += 0.06;
      if (texture.isPaired) f -= 0.05;
    }

    if (polarised) f += 0.20;
    if (thinValue) f -= 0.12;

    f += 0.07 * (opponents - 1).clamp(0, 3);

    f *= sizeScale;
    f += 0.35 * pressure + 0.9 * geoBoost;

    f += (_random.nextDouble() - 0.5) * 0.12;

    f = min(f, max(cap, 0.25));
    return f.clamp(0.25, 2.0);
  }
}
