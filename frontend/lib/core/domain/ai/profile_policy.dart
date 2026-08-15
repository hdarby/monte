import 'dart:math';

import 'package:monte/core/domain/ai/opponent_reads.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_stats.dart';
import 'package:monte/core/domain/ai/open_ranges.dart';
import 'package:monte/core/domain/ai/trigger_observer.dart';
import 'package:monte/core/domain/ai/preflop_ranges.dart';
import 'package:monte/core/domain/ai/stack_context.dart';
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
    OpponentReads? reads,
    TriggerObserver? triggers,
  }) : _random = random ?? Random(),
       _ranges =
           ranges ??
           PreflopRanges.forTargets(
             vpipTarget: profile.strategicBaseline.vpipTarget,
             pfrTarget: profile.strategicBaseline.pfrTarget,
             threeBetTarget: profile.strategicBaseline.threeBetFrequency,
           ) {
    _reads = reads;
    _triggers = triggers;
    _postflop = postflop ?? BotStrategy(random: _random);
  }

  final PlayerProfile profile;
  final Random _random;
  final PreflopRanges _ranges;
  late final OpponentReads? _reads;
  late final DecisionPolicy _postflop;

  /// Records signature moves when they fire (see [TriggerObserver]).
  late final TriggerObserver? _triggers;

  /// Strength cutoffs for escalated preflop pots. Facing a 3-bet you continue
  /// only with a strong range, and only premiums 4-bet/stack off — otherwise two
  /// "3-bet range" hands raise-war to all-in with junk.
  static final double _vs3betCall = PreflopRanges.thresholdForFraction(0.055);
  static final double _stackOff = PreflopRanges.thresholdForFraction(0.025);

  @override
  GameAction decide(PokerGame game, Player p) =>
      game.board.isEmpty ? _preflop(game, p) : _postflop.decide(game, p);

  GameAction _preflop(PokerGame game, Player p) {
    final s = HandStrength.playability(p);
    final toCall = game.callAmount(p);
    final bb = game.bigBlind;
    final raises = game.raiseCountThisRound;
    final canRaise = p.stack > toCall;

    // Position and dead money, for an unopened pot. See [OpenRanges]: opening
    // frequency is driven by how many players are still to act, and by how much
    // is already in the middle. The previous model ranked seats by *postflop*
    // order, which made the small blind the tightest seat at the table when
    // preflop it is second to last, and it only applied at all to profiles
    // carrying the Positional_Warfare characteristic. The multiplier averages
    // 1.0 across the table, so this redistributes aggression by seat rather
    // than inventing more of it and the profile's calibrated VPIP/PFR holds.
    var vpipCut = _ranges.vpip;
    var pfrCut = _ranges.pfr;
    var threeBetCut = _ranges.threeBet;
    final posProf = profile.proficiencyOf('Positional_Warfare');
    if (raises == 0 && toCall <= bb) {
      final m = OpenRanges.forSeat(game, p, positionalProficiency: posProf);
      if (m != 1.0) {
        final b = profile.strategicBaseline;
        pfrCut = PreflopRanges.thresholdForFraction(
          (b.pfrTarget * m).clamp(0.02, 0.90),
        );
        vpipCut = PreflopRanges.thresholdForFraction(
          (b.vpipTarget * m).clamp(0.02, 0.95),
        );
      }
    }

    // Data-driven exploit (scaled by exploit dial × read confidence): 3-bet
    // lighter against an opener who folds to 3-bets too much, and open wider
    // when the blinds behind fold to steals too much. No read ⇒ no change, so a
    // read-less exploiter plays its calibrated baseline rather than a bad prior.
    if (_reads != null) {
      final exploit = ((1 - profile.strategicBaseline.gtoAdherenceWeight) *
              profile.behavioralModifiers.exploitativeWeight)
          .clamp(0.0, 1.0);
      if (exploit > 0) {
        if (raises == 1) {
          final st = _readOfBiggestBettor(game, p);
          if (st != null && st.established) {
            final w = (exploit * st.confidence).clamp(0.0, 1.0);
            final foldy = st.foldTo3betRate - 0.55; // + folds too much
            threeBetCut = (threeBetCut - foldy * 0.12 * w).clamp(0.0, 1.0);
          }
        } else if (raises == 0) {
          final blind = _blindStealRead(game, p);
          if (blind != null && blind.established) {
            final w = (exploit * blind.confidence).clamp(0.0, 1.0);
            final foldy = blind.foldBlindStealRate - 0.55;
            pfrCut = (pfrCut - foldy * 0.10 * w).clamp(0.0, 1.0);
          }
        }
      }
    }

    GameAction raiseBy(double potFraction) {
      final raw = game.minRaiseTo(p) + (game.pot * potFraction).round();
      final raiseTo =
          snapBet(raw, smallBlind: game.smallBlind, bigBlind: game.bigBlind)
              .clamp(game.minRaiseTo(p), game.maxRaiseTo(p));
      return GameAction.raise(raiseTo);
    }

    // Deep-stack discipline: the deeper the effective stack, the tighter the
    // range willing to put it in preflop. At ~100 BB it's the baseline; by a few
    // hundred BB (early in a tournament) only the very top continues a raise war
    // to stacks — nobody ships 600 BB in the first orbit with AK/QQ. 0 at
    // ≤100 BB (normal play, and every existing test, is unchanged).
    final deepFactor = StackContext.of(game, p).depthPressure;
    final stackOff = (_stackOff + 0.12 * deepFactor).clamp(0.0, 1.0);
    final vs3betCall = (_vs3betCall + 0.08 * deepFactor).clamp(0.0, 1.0);

    // Facing a 3-bet or more: only premiums keep raising; a strong-but-not-
    // premium hand flats once; everything else folds. This is what stops the
    // all-in raise wars (and, deep, the first-orbit stack-offs).
    if (raises >= 2) {
      if (s >= stackOff && canRaise) return raiseBy(0.6);
      if (s >= vs3betCall) return const GameAction.call();
      return const GameAction.fold();
    }

    // Facing a single open: 3-bet the top range, flat a *tightened* slice of the
    // VPIP range, otherwise fold.
    //
    // Cold-calling an open is much tighter than opening yourself: you are up
    // against a range that has already shown strength, you are often dominated,
    // and every player still to act can squeeze. Flatting the full opening range
    // here was what pushed half of all flops multiway.
    if (raises == 1) {
      if (s >= threeBetCut && canRaise) return raiseBy(0.6);
      if (s >= _coldCallCut(game, p, vpipCut)) return const GameAction.call();
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

    // Limp re-raise: the old-school trap. First in from early position with a
    // genuine premium, limp and hope somebody raises so the pot can be
    // re-opened over the top. Only from early position (there has to be someone
    // left to do the raising) and only with a hand happy to play a big pot,
    // which is what stops it being an ordinary open-limp leak. The re-raise half
    // needs no code: the `raises >= 2` branch above already ships premiums.
    final limpTrap = profile.proficiencyOf('Limp_Reraise');
    if (limpTrap > 0 &&
        !hasLimper &&
        s >= _stackOff &&
        OpenRanges.playersBehind(game, p) >= 4 &&
        _random.nextDouble() < 0.5 * limpTrap) {
      _triggers?.onFired('Limp_Reraise', p.id, game.round);
      return const GameAction.call();
    }

    // A disciplined pro never *open*-limps: first-in it's raise (PFR range) or
    // fold. *Over*-limping — flatting behind an existing limper — is fine, and is
    // where the VPIP≫PFR gap gets realised, so over-limp the rest of the VPIP
    // range only when a limper is already in.
    if (s >= pfrCut && canRaise) return raiseBy(0.5);
    // Over-limping is cheap, but piling into a family pot with a marginal hand
    // is still how stacks get lost — tighten as the limpers stack up.
    if (hasLimper && s >= _coldCallCut(game, p, vpipCut)) {
      return const GameAction.call();
    }
    return const GameAction.fold();
  }

  /// The strength needed to cold-call, tightened from the opening cut by how
  /// many players are already in and by whether hero will be out of position.
  ///
  /// Keeps pots heads-up far more often, which is both more realistic and what
  /// stops marginal hands building multiway pots they can't win.
  double _coldCallCut(PokerGame game, Player p, double vpipCut) {
    final alreadyIn = game.players
        .where((x) => !identical(x, p) && !x.hasFolded && x.currentBet > 0)
        .length;
    // Each player already committed narrows what is worth calling with.
    var cut = vpipCut + 0.05 + 0.05 * (alreadyIn - 1).clamp(0, 4);

    // Out of position for the whole hand is worth roughly another half-step.
    final n = game.players.length;
    if (n > 1) {
      final heroIdx = game.players.indexOf(p);
      final sbIndex = (game.buttonIndex + 1) % n;
      final rank = ((heroIdx - sbIndex + n) % n) / (n - 1);
      if (rank < 0.5) cut += 0.03;
    }
    return cut.clamp(0.0, 1.0);
  }

  /// The read on the opponent who has put the most chips in this round (the
  /// preflop opener/raiser we'd be 3-betting), or null.
  PlayerStats? _readOfBiggestBettor(PokerGame game, Player p) {
    if (_reads == null) return null;
    final opps =
        game.players.where((x) => x.inHand && !identical(x, p)).toList();
    if (opps.isEmpty) return null;
    opps.sort((a, b) => b.currentBet.compareTo(a.currentBet));
    return _reads.forSeat(opps.first.id);
  }

  /// The read on the blind seat behind us most likely to fold to a steal — the
  /// big blind (or small blind if we're the button), used to size opens wider.
  PlayerStats? _blindStealRead(PokerGame game, Player p) {
    if (_reads == null) return null;
    final n = game.players.length;
    if (n < 2) return null;
    final bbIndex = (game.buttonIndex + 2) % n;
    final bb = game.players[bbIndex];
    if (identical(bb, p) || bb.hasFolded) return null;
    return _reads.forSeat(bb.id);
  }
}
