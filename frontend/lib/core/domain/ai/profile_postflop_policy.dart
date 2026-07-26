import 'dart:math';

import 'package:monte/core/domain/ai/hand_range.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/postflop_equity.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/bet_snap.dart';
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

    // Bet being faced as a fraction of the pot — big bets shrink the perceived
    // range (see `HandRange.narrowedBy`) so a pot-odds continue vs an overbet
    // needs genuine strength, not a stale wide-range equity estimate.
    final potBeforeCall = game.pot - toCall;
    final betFraction = potBeforeCall > 0 ? toCall / potBeforeCall : 0.0;

    // Soul read also sharpens hand-reading: facing a bet, the pro credits the
    // bettor with a tighter, more realistic range (closer to their actual
    // holdings), and spends up to twice the Monte-Carlo runouts resolving the
    // equity against it — so it ranges opponents better than a baseline pro.
    final soul = profile.proficiencyOf('Soul_Read');
    final equityIters = (_equityIterations * (1 + soul)).round();
    final dead = {...p.hole, ...game.board};
    final perceivedTop =
        0.40 * (1 - 0.35 * soul * (betFraction > 0 ? 1.0 : 0.0));
    final range = HandRange.top(perceivedTop, dead: dead).narrowedBy(
      raiseCount: raises,
      street: game.round,
      betFraction: betFraction,
    );
    final eq = PostflopEquity.equity(
      p.hole,
      game.board,
      range,
      iterations: equityIters,
      random: _random,
    );
    final isDraw = eq >= 0.32 && eq <= 0.55;

    // Leverage pressure: some pros hunt for spots to apply maximum pressure —
    // when the pot is heads-up, or when a bet can set an opponent all-in to
    // continue. It ramps aggression and bluffs and sizes up toward the
    // opponent's stack (a jam threat), scaled by the characteristic's proficiency.
    final lev = profile.proficiencyOf('Leverage_Pressure');
    final liveCount = game.players.where((x) => x.inHand).length;
    final minOppStack = game.players
        .where((x) => x.inHand && !identical(x, p))
        .map((x) => x.stack)
        .fold<int>(1 << 30, min);
    final canJam = minOppStack <= game.pot; // a pot-ish bet puts them all-in
    final pv = (lev > 0 && (liveCount == 2 || canJam)) ? lev : 0.0;

    // Soul read is also an in-position gear shift. When the action is checked to
    // the pro (a weakness signal) and every live opponent has already acted — so
    // the pro closes the action in position — they attack harder (thinner value,
    // more bluffs), scaled by proficiency.
    final inPosition = game.players
        .where((x) => x.inHand && !identical(x, p))
        .every((x) => x.hasActedThisRound);
    final sr = (soul > 0 && toCall == 0 && inPosition) ? soul : 0.0;

    // Geometric overbet: on a later street (turn/river) with a clear nut
    // advantage, build the pot with an overbet rather than a standard size,
    // scaled by proficiency.
    final geo = profile.proficiencyOf('Geometric_Overbet_Execution');
    final laterStreet =
        game.round == BettingRound.turn || game.round == BettingRound.river;
    final geoBoost = (geo > 0 && laterStreet && eq > 0.80) ? geo : 0.0;

    GameAction betBy(double fraction) {
      final raw = p.currentBet + (game.pot * fraction).round();
      final to = snapBet(raw, smallBlind: game.smallBlind, bigBlind: bb)
          .clamp(p.currentBet + bb, p.currentBet + p.stack);
      return GameAction.bet(to);
    }

    GameAction raiseBy(double fraction) {
      final raw = game.minRaiseTo(p) + (game.pot * fraction).round();
      final to = snapBet(raw, smallBlind: game.smallBlind, bigBlind: game.bigBlind)
          .clamp(game.minRaiseTo(p), game.maxRaiseTo(p));
      return GameAction.raise(to);
    }

    // No bet to face: value-bet (exploit bets thinner) or bluff (exploit and
    // draws bluff more; GTO still bluffs a small balanced amount).
    if (toCall == 0) {
      final wantsValue = eq > 0.60 - 0.10 * exploit - 0.10 * pv - 0.08 * sr;
      final bluffChance = (0.10 + 0.35 * exploit + 0.30 * pv + 0.30 * sr) *
          ((1 - eq) * 0.6 + (isDraw ? 0.4 : 0.0));
      final wantsBluff = _random.nextDouble() < bluffChance;
      if ((wantsValue || wantsBluff) && p.stack > bb) {
        // Pressure (jam threat) and geometric overbets both size up; the overbet
        // only fires with a nut advantage on a later street.
        return betBy((0.55 * sizeScale + 0.6 * pv + 0.9 * geoBoost).clamp(0.33, 2.0));
      }
      return const GameAction.check();
    }

    // Facing a bet. Continue is the GTO pot-odds line for everyone (bluff-
    // catching stays honest without per-opponent reads). Exploit adds pressure:
    // thinner value-raises and more semibluff-raises.
    final potOdds = toCall / (game.pot + toCall);
    final wantsValueRaise = eq > 0.74 - 0.08 * exploit - 0.10 * pv;
    final wantsBluffRaise =
        isDraw && _random.nextDouble() < 0.05 + 0.30 * exploit + 0.30 * pv;
    if (canRaise && (wantsValueRaise || wantsBluffRaise)) {
      return raiseBy((0.5 * sizeScale + 0.6 * pv + 0.9 * geoBoost).clamp(0.33, 2.0));
    }
    if (eq >= potOdds) return const GameAction.call();
    return const GameAction.fold();
  }
}
