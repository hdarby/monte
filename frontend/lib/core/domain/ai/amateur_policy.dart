import 'dart:math';

import 'package:monte/core/domain/ai/hand_range.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/postflop_equity.dart';
import 'package:monte/core/domain/ai/preflop_ranges.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/bet_snap.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/core/domain/engine/hand_strength.dart';
import 'package:monte/core/domain/engine/player.dart';

/// A weaker, mistake-prone home-game player. It is **not** a different brain
/// philosophy from the pros — it is the same range-aware equity substrate
/// ([ProfilePolicy]/[ProfilePostflopPolicy]) degraded by a single dial,
/// `profile.skill`, plus the profile's own style.
///
/// Every leak is a product of `k = 1 − skill` and a non-negative style bias, so
/// higher skill means strictly closer-to-optimal decisions (monotonic by
/// construction) and a `skill == 1` amateur would collapse onto the disciplined
/// pro thresholds. The leaks modelled:
/// - **noisy hand reads** — Gaussian noise on the equity estimate;
/// - **misjudged ranges** — nits imagine everyone is nitty (overfold), stations
///   imagine everyone bluffs (call down light);
/// - **loose/tight pot-odds discipline** — calling too wide or overfolding;
/// - **distorted value/bluff thresholds**;
/// - **the occasional plausible blunder** (bounded ≤ 8%).
///
/// Preflop leaks are expressed as a *widened* analytic range (loose calling,
/// limping via the VPIP≫PFR gap, wider raise-calling, under-3-betting) rather
/// than ad-hoc thresholds, so the style stays a real poker profile.
class AmateurPolicy implements DecisionPolicy {
  AmateurPolicy(this.profile, {Random? random, PreflopRanges? ranges})
    : _random = random ?? Random(),
      _k = (1.0 - profile.skill).clamp(0.0, 1.0),
      _loose = ((profile.strategicBaseline.vpipTarget - 0.24) / 0.30).clamp(
        0.0,
        1.0,
      ),
      _tight = ((0.24 - profile.strategicBaseline.vpipTarget) / 0.14).clamp(
        0.0,
        1.0,
      ),
      _ranges = ranges ?? _leakyRanges(profile);

  final PlayerProfile profile;
  final Random _random;

  /// Incompetence: `1 − skill`. All leaks scale with this and vanish at 0.
  final double _k;

  /// Style biases derived from VPIP (loose/station vs tight/nit); one is 0.
  final double _loose;
  final double _tight;

  final PreflopRanges _ranges;

  /// Amateurs "think" less than the pros' 160 — cheaper and thematically right;
  /// the shortfall also adds a little natural read noise.
  static const _equityIterations = 96;

  /// Facing escalation, the premium cutoffs that stop junk raise-wars (copied
  /// from `ProfilePolicy` so amateurs stay believable rather than insane).
  /// Amateurs re-raise/4-bet only genuine premiums (top ~1.2%) — recreational
  /// players rarely put in a third bet, so this keeps preflop aggression low.
  static final double _vs3betCall = PreflopRanges.thresholdForFraction(0.055);
  static final double _stackOff = PreflopRanges.thresholdForFraction(0.012);

  /// The profile's preflop targets widened by its leaks: loose players enter
  /// wider (`vpip`), everyone under-raises (passive VPIP≫PFR gap → limps) and
  /// under-3-bets. Bands stay nested.
  static PreflopRanges _leakyRanges(PlayerProfile p) {
    final b = p.strategicBaseline;
    final k = (1.0 - p.skill).clamp(0.0, 1.0);
    final loose = ((b.vpipTarget - 0.24) / 0.30).clamp(0.0, 1.0);
    final vpipEff = (b.vpipTarget * (1 + 0.6 * k * loose)).clamp(0.0, 0.9);
    final pfrEff = (b.pfrTarget * (1 - 0.3 * k)).clamp(0.0, vpipEff);
    final tbEff = (b.threeBetFrequency * (1 - 0.5 * k)).clamp(0.0, pfrEff);
    return PreflopRanges.forTargets(
      vpipTarget: vpipEff,
      pfrTarget: pfrEff,
      threeBetTarget: tbEff,
    );
  }

  /// A standard-normal sample from the injected (seeded) RNG — Box–Muller.
  double _gaussian() {
    final u1 = 1.0 - _random.nextDouble(); // in (0, 1]
    final u2 = _random.nextDouble();
    return sqrt(-2.0 * log(u1)) * cos(2 * pi * u2);
  }

  @override
  GameAction decide(PokerGame game, Player p) =>
      game.board.isEmpty ? _preflop(game, p) : _postflop(game, p);

  GameAction _preflop(PokerGame game, Player p) {
    final s = HandStrength.preflop(p);
    final toCall = game.callAmount(p);
    final bb = game.bigBlind;
    final raises = game.raiseCountThisRound;
    final canRaise = p.stack > toCall;

    GameAction raiseBy(double potFraction) {
      final raw = game.minRaiseTo(p) + (game.pot * potFraction).round();
      final raiseTo =
          snapBet(raw, smallBlind: game.smallBlind, bigBlind: game.bigBlind)
              .clamp(game.minRaiseTo(p), game.maxRaiseTo(p));
      return GameAction.raise(raiseTo);
    }

    // Deep-stack discipline (dormant at ≤100 BB): even a loose amateur doesn't
    // ship hundreds of BB in preflop — the deeper the stack, the tighter the
    // range that keeps raising toward a stack-off.
    final liveOpps = game.players.where((x) => x.inHand && !identical(x, p));
    final deepestOpp =
        liveOpps.isEmpty ? 0 : liveOpps.map((x) => x.stack).reduce(max);
    final effBb = bb > 0 ? min(p.stack, deepestOpp) / bb : 100.0;
    final deepFactor = ((effBb - 100.0) / 200.0).clamp(0.0, 1.0);

    // Facing a 3-bet+: only premiums keep raising; loose amateurs cold-call a
    // touch wider than a pro, but nobody raise-wars junk to all-in.
    if (raises >= 2) {
      final stackOff = (_stackOff + 0.12 * deepFactor).clamp(0.0, 1.0);
      if (s >= stackOff && canRaise) return raiseBy(0.6);
      final vs3Call =
          (_vs3betCall - 0.02 * _k * _loose + 0.08 * deepFactor).clamp(0.0, 1.0);
      if (s >= vs3Call) return const GameAction.call();
      return const GameAction.fold();
    }

    // Facing a single open: 3-bet the top range, flat the (widened) VPIP range.
    if (raises == 1) {
      if (s >= _ranges.threeBet && canRaise) return raiseBy(0.6);
      if (s >= _ranges.vpip) return const GameAction.call();
      return const GameAction.fold();
    }

    // Unraised.
    if (toCall == 0) {
      if (s >= _ranges.pfr && p.stack > bb) return raiseBy(0.5);
      return const GameAction.check();
    }
    // First in / over limpers: raise the PFR range; the rest of the VPIP range
    // limps along (the passive gap), everything else folds.
    if (s >= _ranges.pfr && canRaise) return raiseBy(0.5);
    if (s >= _ranges.vpip) return const GameAction.call();
    return const GameAction.fold();
  }

  GameAction _postflop(PokerGame game, Player p) {
    final toCall = game.callAmount(p);
    final bb = game.bigBlind;
    final raises = game.raiseCountThisRound;
    final canRaise = p.stack > toCall;
    final onRiver = game.round == BettingRound.river;

    // Deep-stack commitment discipline (dormant ≤100 BB): even a rec doesn't get
    // hundreds of BB in with a marginal hand. deepFactor 0 at ≤100 BB → normal
    // (leaky) play; ramps by ~300 BB. Kept lighter than the pro gate so recs
    // still stack off a touch lighter (they remain the losers).
    final effBb = bb > 0 ? (p.totalContributed + p.stack) / bb : 100.0;
    final deepFactor = ((effBb - 100.0) / 200.0).clamp(0.0, 1.0);

    // NB: recreational players are deliberately left overvaluing hands multiway
    // and splashing in deep pots — that's a realistic leak and a big part of why
    // they lose to pros (patching it makes them beat a pro field). Only the pro
    // brain (ProfilePostflopPolicy) gets the multiway/deep-stack discipline.
    final adherence = profile.strategicBaseline.gtoAdherenceWeight;
    final exploit =
        ((1 - adherence) * profile.behavioralModifiers.exploitativeWeight)
            .clamp(0.0, 1.0);
    final sizeScale =
        profile.behavioralModifiers.riskPremiumCoefficient.clamp(0.6, 1.6);

    // Perceived range: a nit imagines nits (narrow → overfolds to aggression), a
    // station imagines bluffers (wide → calls down light). Pro reads top 40%.
    // Bet being faced as a fraction of the pot — big bets shrink the perceived
    // range (see `HandRange.narrowedBy`). A read-noisy amateur still trails a
    // pro here, but even a station stops crediting an overbet with a wide range.
    final potBeforeCall = game.pot - toCall;
    final betFraction = potBeforeCall > 0 ? toCall / potBeforeCall : 0.0;
    final dead = {...p.hole, ...game.board};
    final perceivedTop =
        (0.40 - 0.20 * _k * _tight + 0.10 * _k * _loose).clamp(0.15, 0.65);
    final range = HandRange.top(perceivedTop, dead: dead).narrowedBy(
      raiseCount: raises,
      street: game.round,
      betFraction: betFraction,
    );
    final eq = PostflopEquity.equity(
      p.hole,
      game.board,
      range,
      iterations: _equityIterations,
      random: _random,
    );
    // Draw recognition uses the honest equity; decisions use the misread one.
    // Read-noise is the primary, *style-independent* skill dial: even a
    // neutral-style amateur misreads hands, so it trails every pro. Kept
    // moderate — the realism guards below stop it from producing absurd actions
    // (calling off with air, shipping junk) while it still costs EV believably.
    final isDraw = eq >= 0.32 && eq <= 0.55;
    final noisy = (eq + _gaussian() * 0.26 * _k).clamp(0.0, 1.0);

    GameAction betBy(double fraction) {
      final raw = p.currentBet + (game.pot * fraction).round();
      final to = snapBet(raw, smallBlind: game.smallBlind, bigBlind: bb)
          .clamp(p.currentBet + bb, p.currentBet + p.stack);
      return GameAction.bet(to);
    }

    GameAction raiseBy(double fraction) {
      final raw = game.minRaiseTo(p) + (game.pot * fraction).round();
      final to =
          snapBet(raw, smallBlind: game.smallBlind, bigBlind: game.bigBlind)
              .clamp(game.minRaiseTo(p), game.maxRaiseTo(p));
      return GameAction.raise(to);
    }

    // Occasional plausible blunder (bounded), scaled purely by incompetence.
    // Kept believable: a small stab or spew-fold, never a big call-off with air.
    final blunderP = (0.12 * _k).clamp(0.0, 0.08);
    if (_random.nextDouble() < blunderP) {
      if (toCall == 0) {
        return (_random.nextBool() && p.stack > bb)
            ? betBy((0.5 * sizeScale).clamp(0.33, 0.9)) // spazz stab
            : const GameAction.check();
      }
      // Facing a bet: spazz-fold, or a small overcall — never call off a big bet.
      if (toCall > 4 * bb) return const GameAction.fold();
      return _random.nextBool()
          ? const GameAction.fold()
          : const GameAction.call();
    }

    // No bet to face: value-bet or bluff, with style-shifted thresholds.
    if (toCall == 0) {
      // The river bar is higher — thin river value bets just get called by
      // better and bloat the pot into a stack-off, so amateurs value-bet the
      // end more selectively.
      final valueCut =
          ((0.60 - 0.08 * exploit) + 0.12 * _k * _tight - 0.10 * _k * _loose +
                  (onRiver ? 0.10 : 0.0))
              .clamp(0.40, 0.90);
      final wantsValue = noisy > valueCut;
      final bluffChance = ((0.10 + 0.30 * exploit) + 0.15 * _k * _loose) *
          ((1 - noisy) * 0.6 + (isDraw ? 0.4 : 0.0));
      final wantsBluff = _random.nextDouble() < bluffChance;
      if ((wantsValue || wantsBluff) && p.stack > bb) {
        return betBy((0.55 * sizeScale).clamp(0.33, 0.9));
      }
      return const GameAction.check();
    }

    // Facing a bet.
    final potOdds = toCall / (game.pot + toCall);
    final commit = toCall / (p.stack + toCall); // share of remaining stack risked

    // River discipline floor: never call a real bet with a hand that can't beat
    // a pair. Amateurs pay off with weak *made* hands (stations call with a
    // pair), but not with literal air — no calling off with king-high on the
    // end. Uses the actual made hand, so noise can't override it.
    if (onRiver && toCall > bb) {
      final made = HandEvaluator.evaluate([...p.hole, ...game.board]).rank;
      if (made == HandRank.highCard) return const GameAction.fold();
    }

    // Short-stack / committed play: once calling would put more than ~40% of the
    // remaining stack in, amateurs jam or fold — they rarely just flat a big
    // chunk. Continue only with a genuine hand or live draw (honest-equity floor
    // so a noisy read can't ship air), and prefer shoving for the fold equity.
    if (commit > 0.4) {
      final strongEnough = noisy >= 0.45 && eq >= 0.42;
      if (!strongEnough || !_deepCommitOk(p, toCall, eq, deepFactor)) {
        return const GameAction.fold();
      }
      return canRaise
          ? GameAction.raise(game.maxRaiseTo(p)) // jam
          : const GameAction.call(); // already facing a (near) all-in
    }

    // Not committed: a value-raise needs *genuine* strength (honest equity), not
    // just a noisy read — so amateurs don't ship weak hands. And don't re-raise
    // into an already-raised pot without a premium: this stops the multi-raise
    // all-in wars with holdings that don't support them.
    final valueRaiseCut =
        ((0.74 - 0.06 * exploit) + 0.12 * _k * _tight - 0.08 * _k * _loose)
            .clamp(0.55, 0.95);
    final wantsValueRaise = noisy > valueRaiseCut && eq > 0.60;
    final wantsBluffRaise = isDraw &&
        raises == 0 &&
        _random.nextDouble() < 0.04 + 0.20 * exploit + 0.06 * _k * _loose;
    final mayRaise = canRaise && (raises == 0 || eq > 0.80);
    if (mayRaise && (wantsValueRaise || wantsBluffRaise)) {
      final r = raiseBy((0.5 * sizeScale).clamp(0.33, 0.9));
      if (_deepCommitOk(p, r.amount - p.currentBet, eq, deepFactor)) return r;
    }

    // Discipline leak: stations call a bit below pot odds, nits overfold above —
    // bounded so it stays a believable leak, not a spew.
    final callThreshold =
        (potOdds + 0.10 * _k * _tight - 0.10 * _k * _loose).clamp(0.0, 1.0);
    if (noisy >= callThreshold) return const GameAction.call();
    return const GameAction.fold();
  }

  /// Deep-stack commitment gate: the larger the fraction of a deep stack an
  /// action commits, the stronger the hand must be. Lighter than the pro gate
  /// (recs stack off a bit looser, staying net losers), dormant at ≤100 BB.
  bool _deepCommitOk(Player p, int risked, double equity, double deepFactor) {
    if (deepFactor <= 0 || risked <= 0) return true;
    final effTotal = p.totalContributed + p.stack;
    if (effTotal <= 0) return true;
    final commitFrac = ((p.totalContributed + risked) / effTotal).clamp(0.0, 1.0);
    if (commitFrac < 0.32) return true;
    final bar = (0.49 + 0.44 * commitFrac * deepFactor).clamp(0.0, 0.92);
    return equity >= bar;
  }
}
