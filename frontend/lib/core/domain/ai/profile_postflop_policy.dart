import 'dart:math';

import 'package:monte/core/domain/ai/hand_range.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/postflop_equity.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

/// A fast, range-aware postflop brain for [PlayerProfile] bots that expresses
/// the GTO ↔ exploitative dial without a full search.
///
/// It plays hero equity vs the villain's perceived range ([PostflopEquity]).
/// A perfectly disciplined profile (`gtoAdherenceWeight == 1`) plays that equity
/// straight: continue on pot odds, value-bet strong holdings, bluff at a small
/// balanced frequency. As adherence drops and `exploitativeWeight` rises, the
/// profile deviates toward *applying pressure* — thinner value, more bluffs,
/// more bluff-raises — against a **static population prior** (the pool folds a
/// touch too often to aggression). Per-opponent reads (via `OpponentModel`) are
/// a later refinement; the exploit strength here is the confidence-free part of
/// Appendix B: `exploit = (1 − gtoAdherenceWeight) · exploitativeWeight`.
class ProfilePostflopPolicy implements DecisionPolicy {
  ProfilePostflopPolicy(this.profile, {Random? random})
    : _random = random ?? Random();

  final PlayerProfile profile;
  final Random _random;

  static const _equityIterations = 160;

  @override
  GameAction decide(PokerGame game, Player p) {
    // Preflop is the calibrated frequency layer's job; this brain is postflop.
    if (game.board.isEmpty) {
      // Defensive: a profile bot should never reach here preflop, but continue
      // cheaply on pot odds rather than throw.
      final toCall = game.callAmount(p);
      return toCall == 0 ? const GameAction.check() : const GameAction.call();
    }

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

    final dead = {...p.hole, ...game.board};
    final range = HandRange.top(0.40, dead: dead)
        .narrowedBy(raiseCount: raises, street: game.round);
    final eq = PostflopEquity.equity(
      p.hole,
      game.board,
      range,
      iterations: _equityIterations,
      random: _random,
    );
    final isDraw = eq >= 0.32 && eq <= 0.55;

    GameAction betBy(double fraction) {
      final size = (game.pot * fraction).round().clamp(bb, p.stack);
      return GameAction.bet(p.currentBet + size);
    }

    GameAction raiseBy(double fraction) {
      final to = (game.minRaiseTo(p) + (game.pot * fraction).round()).clamp(
        game.minRaiseTo(p),
        game.maxRaiseTo(p),
      );
      return GameAction.raise(to);
    }

    // No bet to face: value-bet (exploit bets thinner) or bluff (exploit and
    // draws bluff more; GTO still bluffs a small balanced amount).
    if (toCall == 0) {
      final wantsValue = eq > 0.60 - 0.10 * exploit;
      final bluffChance =
          (0.10 + 0.35 * exploit) * ((1 - eq) * 0.6 + (isDraw ? 0.4 : 0.0));
      final wantsBluff = _random.nextDouble() < bluffChance;
      if ((wantsValue || wantsBluff) && p.stack > bb) {
        return betBy((0.55 * sizeScale).clamp(0.33, 1.0));
      }
      return const GameAction.check();
    }

    // Facing a bet. Continue is the GTO pot-odds line for everyone (bluff-
    // catching stays honest without per-opponent reads). Exploit adds pressure:
    // thinner value-raises and more semibluff-raises.
    final potOdds = toCall / (game.pot + toCall);
    final wantsValueRaise = eq > 0.74 - 0.08 * exploit;
    final wantsBluffRaise =
        isDraw && _random.nextDouble() < 0.05 + 0.30 * exploit;
    if (canRaise && (wantsValueRaise || wantsBluffRaise)) {
      return raiseBy((0.5 * sizeScale).clamp(0.33, 1.2));
    }
    if (eq >= potOdds) return const GameAction.call();
    return const GameAction.fold();
  }
}
