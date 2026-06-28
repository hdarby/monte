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
    final bb = game.bigBlind;
    final preflop = game.board.isEmpty;
    final raises = game.raiseCountThisRound;
    final aggr = profile.aggression;
    final bluff = profile.bluffFrequency;
    final tight = profile.tightness;
    final risk = profile.riskTolerance;
    final canRaise = p.stack > toCall;

    GameAction raiseBy(double fraction) {
      final to = (game.minRaiseTo(p) + (game.pot * fraction).round()).clamp(
        game.minRaiseTo(p),
        game.maxRaiseTo(p),
      );
      return GameAction.raise(to);
    }

    // No bet to face: check, or bet for value (threshold falls with aggression)
    // or as a bluff (more likely with weaker hands and a higher bluff axis).
    if (toCall == 0) {
      final wantsValue = s > 0.72 - 0.30 * aggr;
      final wantsBluff = _random.nextDouble() < bluff * (1 - s) * 0.6;
      if ((wantsValue || wantsBluff) && p.stack > bb) {
        final size = (game.pot * (0.4 + 0.6 * aggr)).round().clamp(bb, p.stack);
        return GameAction.bet(p.currentBet + size);
      }
      return const GameAction.check();
    }

    final potOdds = toCall / (game.pot + toCall);
    final callThreshold = potOdds * (1 + 0.8 * tight) - 0.15 * risk;

    // Facing a 3-bet or more: only genuinely strong hands re-raise — otherwise
    // two "raise range" hands escalate to an all-in with junk. Continue with a
    // strong hand, else fold.
    if (raises >= 2) {
      if (canRaise && s > 0.90 - 0.12 * aggr) return raiseBy(0.5 + 0.4 * aggr);
      final floor = preflop ? 0.60 : 0.45;
      if (s >= floor && s >= callThreshold) return const GameAction.call();
      return const GameAction.fold();
    }

    // Unraised or facing a single raise: value/bluff raise, then call/fold by
    // pot odds (scaled by tightness and risk tolerance).
    final wantsRaiseValue = s > 0.82 - 0.30 * aggr;
    final wantsRaiseBluff = _random.nextDouble() < bluff * (1 - s) * 0.4;
    if (canRaise && (wantsRaiseValue || wantsRaiseBluff)) {
      return raiseBy(0.3 + 0.5 * aggr);
    }
    if (s >= callThreshold) return const GameAction.call();
    return const GameAction.fold();
  }
}
