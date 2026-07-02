import 'dart:math';

import 'package:monte/core/domain/ai/hand_range.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/postflop_equity.dart';
import 'package:monte/core/domain/ai/preflop_ranges.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/bet_snap.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/game.dart';
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
  static final double _vs3betCall = PreflopRanges.thresholdForFraction(0.055);
  static final double _stackOff = PreflopRanges.thresholdForFraction(0.025);

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

    // Facing a 3-bet+: only premiums keep raising; loose amateurs cold-call a
    // touch wider than a pro, but nobody raise-wars junk to all-in.
    if (raises >= 2) {
      if (s >= _stackOff && canRaise) return raiseBy(0.6);
      final vs3Call = _vs3betCall - 0.02 * _k * _loose;
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

    final adherence = profile.strategicBaseline.gtoAdherenceWeight;
    final exploit =
        ((1 - adherence) * profile.behavioralModifiers.exploitativeWeight)
            .clamp(0.0, 1.0);
    final sizeScale =
        profile.behavioralModifiers.riskPremiumCoefficient.clamp(0.6, 1.6);

    // Perceived range: a nit imagines nits (narrow → overfolds to aggression), a
    // station imagines bluffers (wide → calls down light). Pro reads top 40%.
    final dead = {...p.hole, ...game.board};
    final perceivedTop =
        (0.40 - 0.20 * _k * _tight + 0.10 * _k * _loose).clamp(0.15, 0.65);
    final range = HandRange.top(perceivedTop, dead: dead)
        .narrowedBy(raiseCount: raises, street: game.round);
    final eq = PostflopEquity.equity(
      p.hole,
      game.board,
      range,
      iterations: _equityIterations,
      random: _random,
    );
    // Draw recognition uses the honest equity; decisions use the misread one.
    // Read-noise is the primary, *style-independent* skill dial: even a
    // neutral-style amateur misreads hands, so it trails every pro.
    final isDraw = eq >= 0.32 && eq <= 0.55;
    final noisy = (eq + _gaussian() * 0.30 * _k).clamp(0.0, 1.0);

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
    final blunderP = (0.12 * _k).clamp(0.0, 0.10);
    if (_random.nextDouble() < blunderP) {
      if (toCall == 0) {
        return (_random.nextBool() && p.stack > bb)
            ? betBy((0.5 * sizeScale).clamp(0.33, 1.0)) // spazz stab
            : const GameAction.check();
      }
      // Facing a bet: overcall (station off) or spew-fold — both legal.
      return _random.nextBool()
          ? const GameAction.fold()
          : const GameAction.call();
    }

    // No bet to face: value-bet or bluff, with style-shifted thresholds.
    if (toCall == 0) {
      final valueCut =
          ((0.60 - 0.10 * exploit) + 0.12 * _k * _tight - 0.10 * _k * _loose)
              .clamp(0.30, 0.85);
      final wantsValue = noisy > valueCut;
      final bluffChance = ((0.10 + 0.35 * exploit) + 0.25 * _k * _loose) *
          ((1 - noisy) * 0.6 + (isDraw ? 0.4 : 0.0));
      final wantsBluff = _random.nextDouble() < bluffChance;
      if ((wantsValue || wantsBluff) && p.stack > bb) {
        return betBy((0.55 * sizeScale).clamp(0.33, 1.0));
      }
      return const GameAction.check();
    }

    // Facing a bet.
    final potOdds = toCall / (game.pot + toCall);
    final valueRaiseCut =
        ((0.74 - 0.08 * exploit) + 0.12 * _k * _tight - 0.10 * _k * _loose)
            .clamp(0.40, 0.95);
    final wantsValueRaise = noisy > valueRaiseCut;
    final wantsBluffRaise =
        isDraw && _random.nextDouble() < 0.05 + 0.30 * exploit + 0.10 * _k * _loose;
    if (canRaise && (wantsValueRaise || wantsBluffRaise)) {
      return raiseBy((0.5 * sizeScale).clamp(0.33, 1.2));
    }
    // Discipline leak: stations call below pot odds, nits overfold above.
    final callThreshold =
        (potOdds + 0.10 * _k * _tight - 0.16 * _k * _loose).clamp(0.0, 1.0);
    if (noisy >= callThreshold) return const GameAction.call();
    return const GameAction.fold();
  }
}
