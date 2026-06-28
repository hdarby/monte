import 'dart:math';

import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/preflop_ranges.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/bot.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_strength.dart';
import 'package:monte/core/domain/engine/player.dart';

/// Phase 1 of the player-profile engine: a policy whose **preflop** play is
/// calibrated to the profile's VPIP / PFR / 3-bet targets via [PreflopRanges].
/// Postflop is delegated to the competent heuristic baseline for now (Phase 1 is
/// about realising the preflop frequencies; skill/exploits/triggers come later).
class ProfilePolicy implements DecisionPolicy {
  /// [ranges] lets a caller inject calibrated thresholds (see
  /// `ProfileCalibrator`); when omitted they're derived analytically from the
  /// profile's targets (good for VPIP, looser for PFR/3-bet).
  ProfilePolicy(this.profile, {Random? random, PreflopRanges? ranges})
    : _random = random ?? Random(),
      _ranges =
          ranges ??
          PreflopRanges.forTargets(
            vpipTarget: profile.strategicBaseline.vpipTarget,
            pfrTarget: profile.strategicBaseline.pfrTarget,
            threeBetTarget: profile.strategicBaseline.threeBetFrequency,
          ) {
    _postflop = BotStrategy(random: _random);
  }

  final PlayerProfile profile;
  final Random _random;
  final PreflopRanges _ranges;
  late final BotStrategy _postflop;

  /// Strength cutoffs for escalated preflop pots. Facing a 3-bet you continue
  /// only with a strong range, and only premiums 4-bet/stack off — otherwise two
  /// "3-bet range" hands raise-war to all-in with junk.
  static final double _vs3betCall = PreflopRanges.thresholdForFraction(0.055);
  static final double _stackOff = PreflopRanges.thresholdForFraction(0.025);

  @override
  GameAction decide(PokerGame game, Player p) =>
      game.board.isEmpty ? _preflop(game, p) : _postflop.decide(game, p);

  GameAction _preflop(PokerGame game, Player p) {
    final s = HandStrength.preflop(p);
    final toCall = game.callAmount(p);
    final bb = game.bigBlind;
    final raises = game.raiseCountThisRound;
    final canRaise = p.stack > toCall;

    GameAction raiseBy(double potFraction) {
      final raiseTo = (game.minRaiseTo(p) + (game.pot * potFraction).round())
          .clamp(game.minRaiseTo(p), game.maxRaiseTo(p));
      return GameAction.raise(raiseTo);
    }

    // Facing a 3-bet or more: only premiums keep raising; a strong-but-not-
    // premium hand flats once; everything else folds. This is what stops the
    // all-in raise wars.
    if (raises >= 2) {
      if (s >= _stackOff && canRaise) return raiseBy(0.6);
      if (s >= _vs3betCall) return const GameAction.call();
      return const GameAction.fold();
    }

    // Facing a single open: 3-bet the top range, flat the rest of the VPIP
    // range, otherwise fold.
    if (raises == 1) {
      if (s >= _ranges.threeBet && canRaise) return raiseBy(0.6);
      if (s >= _ranges.vpip) return const GameAction.call();
      return const GameAction.fold();
    }

    // Unraised.
    if (toCall == 0) {
      // Big blind option: raise the PFR range, else take the free flop.
      if (s >= _ranges.pfr && p.stack > bb) return raiseBy(0.5);
      return const GameAction.check();
    }
    // First in (or over limpers): open-raise the PFR range; the rest of the
    // VPIP range limps along, everything else folds.
    if (s >= _ranges.pfr && canRaise) return raiseBy(0.5);
    if (s >= _ranges.vpip) return const GameAction.call();
    return const GameAction.fold();
  }
}
