import 'dart:math';

import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/preflop_ranges.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/bet_snap.dart';
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
  ///
  /// [postflop] is the brain used once there's a board — inject an
  /// `IsmctsEngine` (depth scaled by `gtoAdherenceWeight`) for skilled play, or
  /// leave it as the fast heuristic baseline (used during calibration, which
  /// only measures preflop frequencies).
  ProfilePolicy(
    this.profile, {
    Random? random,
    PreflopRanges? ranges,
    DecisionPolicy? postflop,
  }) : _random = random ?? Random(),
       _ranges =
           ranges ??
           PreflopRanges.forTargets(
             vpipTarget: profile.strategicBaseline.vpipTarget,
             pfrTarget: profile.strategicBaseline.pfrTarget,
             threeBetTarget: profile.strategicBaseline.threeBetFrequency,
           ) {
    _postflop = postflop ?? BotStrategy(random: _random);
  }

  final PlayerProfile profile;
  final Random _random;
  final PreflopRanges _ranges;
  late final DecisionPolicy _postflop;

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

    // Positional warfare: skew the entry/raise cutoffs by seat — tighter in
    // early position, looser near the button. The shift is mean-zero across the
    // rotating button, so the player's *average* VPIP/PFR (and calibration) is
    // unchanged; only its distribution across positions tilts.
    var vpipCut = _ranges.vpip;
    var pfrCut = _ranges.pfr;
    var threeBetCut = _ranges.threeBet;
    final posProf = profile.proficiencyOf('Positional_Warfare');
    if (posProf > 0) {
      final n = game.players.length;
      final heroIdx = game.players.indexOf(p);
      final sbIndex = (game.buttonIndex + 1) % n;
      // 0.0 = first to act postflop (SB, earliest), 1.0 = button (latest).
      final rank = n <= 1 ? 0.5 : ((heroIdx - sbIndex + n) % n) / (n - 1);
      final shift = 0.20 * posProf * (0.5 - rank); // + tighter early, − looser late
      vpipCut = (vpipCut + shift).clamp(0.0, 1.0);
      pfrCut = (pfrCut + shift).clamp(0.0, 1.0);
      threeBetCut = (threeBetCut + shift).clamp(0.0, 1.0);
    }

    GameAction raiseBy(double potFraction) {
      final raw = game.minRaiseTo(p) + (game.pot * potFraction).round();
      final raiseTo =
          snapBet(raw, smallBlind: game.smallBlind, bigBlind: game.bigBlind)
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
      if (s >= threeBetCut && canRaise) return raiseBy(0.6);
      if (s >= vpipCut) return const GameAction.call();
      return const GameAction.fold();
    }

    // Unraised.
    if (toCall == 0) {
      // Big blind option: raise the PFR range, else take the free flop.
      if (s >= pfrCut && p.stack > bb) return raiseBy(0.5);
      return const GameAction.check();
    }
    // Unraised, hero must call the big blind (so hero isn't the BB). Is anyone
    // already limping? A limper is a live opponent who has *acted* and is sitting
    // at exactly the big blind (`hasActedThisRound` excludes the BB, whose blind
    // is forced and whose option is still live).
    final hasLimper = game.players.any(
      (x) =>
          !identical(x, p) &&
          !x.hasFolded &&
          x.hasActedThisRound &&
          x.currentBet == bb,
    );

    // A disciplined pro never *open*-limps: first-in it's raise (PFR range) or
    // fold. *Over*-limping — flatting behind an existing limper — is fine, and is
    // where the VPIP≫PFR gap gets realised, so over-limp the rest of the VPIP
    // range only when a limper is already in.
    if (s >= pfrCut && canRaise) return raiseBy(0.5);
    if (hasLimper && s >= vpipCut) return const GameAction.call();
    return const GameAction.fold();
  }
}
