import 'dart:math';

import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_strength.dart';
import 'package:monte/core/domain/engine/player.dart';

/// A fast, fully personality-driven policy. The four [PersonalityProfile] axes
/// shape the fold/call/bet/raise thresholds so that style is both a usable
/// standalone bot and the default self-/opponent-model for the search's
/// rollouts.
///
/// The axes are wired to be monotonic: more [PersonalityProfile.tightness] folds
/// more (lower VPIP); more [PersonalityProfile.aggression] bets/raises more;
/// more [PersonalityProfile.bluffFrequency] adds aggression with weak hands;
/// more [PersonalityProfile.riskTolerance] calls a touch wider.
class PersonalityPolicy implements DecisionPolicy {
  PersonalityPolicy(this.profile, {Random? random})
    : _random = random ?? Random();

  final PersonalityProfile profile;
  final Random _random;

  @override
  GameAction decide(PokerGame game, Player p) {
    final s = HandStrength.estimate(game, p);
    final toCall = game.callAmount(p);
    final aggr = profile.aggression;
    final bluff = profile.bluffFrequency;
    final tight = profile.tightness;
    final risk = profile.riskTolerance;

    // No bet to face: check, or bet for value (threshold falls with aggression)
    // or as a bluff (more likely with weaker hands and a higher bluff axis).
    if (toCall == 0) {
      final wantsValue = s > 0.72 - 0.30 * aggr;
      final wantsBluff = _random.nextDouble() < bluff * (1 - s) * 0.6;
      if ((wantsValue || wantsBluff) && p.stack > game.bigBlind) {
        final fraction = 0.4 + 0.6 * aggr;
        final size = (game.pot * fraction).round().clamp(
          game.bigBlind,
          p.stack,
        );
        return GameAction.bet(p.currentBet + size);
      }
      return const GameAction.check();
    }

    // Facing a bet. Raise for value/bluff first (thresholds fall with aggression
    // and bluff).
    final canRaise = p.stack > toCall;
    final wantsRaiseValue = s > 0.82 - 0.30 * aggr;
    final wantsRaiseBluff = _random.nextDouble() < bluff * (1 - s) * 0.4;
    if (canRaise && (wantsRaiseValue || wantsRaiseBluff)) {
      final extra = (game.pot * (0.3 + 0.5 * aggr)).round();
      final raiseTo = game.minRaiseTo(p) + extra;
      return GameAction.raise(
        raiseTo.clamp(game.minRaiseTo(p), game.maxRaiseTo(p)),
      );
    }

    // Otherwise call or fold by pot odds, scaled by tightness (need more equity)
    // and risk tolerance (call a little wider).
    final potOdds = toCall / (game.pot + toCall);
    final callThreshold = potOdds * (1 + 0.8 * tight) - 0.15 * risk;
    if (s >= callThreshold) return const GameAction.call();
    return const GameAction.fold();
  }
}
