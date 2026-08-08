import 'dart:math';

import 'package:monte/core/domain/ai/hand_range.dart';
import 'package:monte/core/domain/ai/opponent_reads.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_stats.dart';
import 'package:monte/core/domain/ai/postflop_equity.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/bet_snap.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';
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
  ProfilePostflopPolicy(this.profile, {Random? random, OpponentReads? reads})
    : _random = random ?? Random() {
    _reads = reads;
  }

  final PlayerProfile profile;
  final Random _random;

  /// Accumulated reads on the opponents (null = no data / GTO seat).
  late final OpponentReads? _reads;

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

    // Multiway + stack depth. Equity vs a single villain range is a heads-up
    // number; in a bloated multiway pot a bot must clear a much higher bar, so
    // count the live opponents and read the pot as multiway below.
    final liveOpps = game.players
        .where((x) => x.inHand && !identical(x, p))
        .toList();
    final liveOpp = liveOpps.length;
    final deepestOpp =
        liveOpps.isEmpty ? 0 : liveOpps.map((x) => x.stack).reduce(max);
    // Effective chips still behind (what a stack-off risks), in big blinds.
    // Genuinely deep stacks (100s of BB — e.g. early in a tournament) demand a
    // much stronger hand before building a big pot; at a normal ~100 BB the bot
    // plays its baseline. 0 at ≤100 BB, ramping to 1 by ~300 BB deep, so normal
    // cash play is unchanged and only deep bloat is disciplined.
    final effStack = min(p.stack, deepestOpp);
    final stackBb = bb > 0 ? effStack / bb : 100.0;
    final deepFactor = ((stackBb - 100.0) / 200.0).clamp(0.0, 1.0);

    final adherence = profile.strategicBaseline.gtoAdherenceWeight;
    final exploit =
        ((1 - adherence) * profile.behavioralModifiers.exploitativeWeight)
            .clamp(0.0, 1.0);
    final sizeScale =
        profile.behavioralModifiers.riskPremiumCoefficient.clamp(0.6, 1.6);

    // Data-driven exploit: instead of deviating on a fixed population prior, an
    // exploitative pro adjusts to the *specific* opponent's observed tendencies,
    // scaled by how much of a read it has (confidence) and how exploitative it
    // is. With no data these terms are ~0, so it plays its GTO baseline (which
    // is why a read-less exploiter no longer bleeds to a GTO reg).
    var rBluffMore = 0.0; // bump bluffing vs a player who overfolds
    var rValueThin = 0.0; // thin value vs a station who won't fold
    var rRespect = 0.0; // fold more to a passive player's bet
    final st = _representativeOpponent(game, p, toCall);
    if (st != null && st.established) {
      final w = (exploit * st.confidence).clamp(0.0, 1.0);
      final foldy = st.foldToCbetRate - 0.45; // + overfolds, − calls too much
      rBluffMore = (foldy * 2.0 * w).clamp(-0.30, 0.30);
      rValueThin = ((-foldy) * 0.8 * w).clamp(0.0, 0.15);
      if (toCall > 0) {
        final passive = (1.0 - st.aggressionFactor).clamp(0.0, 1.0);
        rRespect = (passive * 0.12 * w).clamp(0.0, 0.12);
      }
    }

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
    final eq = PostflopEquity.equityMultiway(
      p.hole,
      game.board,
      range,
      opponents: liveOpp,
      iterations: equityIters,
      random: _random,
    );
    final isDraw = eq >= 0.32 && eq <= 0.55;

    // Leverage pressure: some pros hunt for spots to apply maximum pressure —
    // when the pot is heads-up, or when a bet can set an opponent all-in to
    // continue. It ramps aggression and bluffs and sizes up toward the
    // opponent's stack (a jam threat), scaled by the characteristic's proficiency.
    final lev = profile.proficiencyOf('Leverage_Pressure');
    final liveCount = liveOpp + 1;
    final minOppStack =
        liveOpps.isEmpty ? 1 << 30 : liveOpps.map((x) => x.stack).reduce(min);
    final canJam = minOppStack <= game.pot; // a pot-ish bet puts them all-in
    // Don't ramp toward a jam when deep unless the hand genuinely wants stacks in
    // — leverage is for shallow/committed spots, not 200BB-deep bloat.
    final pv = (lev > 0 && (liveCount == 2 || canJam) && (deepFactor < 0.5 || eq > 0.80))
        ? lev
        : 0.0;

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
      // rValueThin lowers the bar vs a station (they pay off thinner value);
      // rBluffMore adds bluff frequency vs a player who overfolds.
      final wantsValue = eq >
          0.60 - 0.10 * exploit - 0.10 * pv - 0.08 * sr + 0.10 * deepFactor - rValueThin;
      final bluffChance = (0.10 + 0.35 * exploit + 0.30 * pv + 0.30 * sr) *
              ((1 - eq) * 0.6 + (isDraw ? 0.4 : 0.0)) +
          0.4 * rBluffMore;
      final wantsBluff = _random.nextDouble() < bluffChance;
      if ((wantsValue || wantsBluff) && p.stack > bb) {
        // Pressure (jam threat) and geometric overbets both size up; the overbet
        // only fires with a nut advantage on a later street.
        final b = betBy((0.55 * sizeScale + 0.6 * pv + 0.9 * geoBoost).clamp(0.33, 2.0));
        final risked = b.amount - p.currentBet;
        if (_deepCommitOk(p, risked, eq, deepFactor) &&
            _flushCommitOk(game, p, risked, eq)) {
          return b;
        }
      }
      return const GameAction.check();
    }

    // Facing a bet. Continue is the GTO pot-odds line for everyone (bluff-
    // catching stays honest without per-opponent reads). Exploit adds pressure:
    // thinner value-raises and more semibluff-raises.
    final potOdds = toCall / (game.pot + toCall);
    // Deep, only raise for value with a hand that wants a big pot; deep-bluff-
    // raises also need more, so we don't spew stacks off building bloated pots.
    final wantsValueRaise =
        eq > 0.74 - 0.08 * exploit - 0.10 * pv + 0.12 * deepFactor;
    final wantsBluffRaise = isDraw &&
        _random.nextDouble() < 0.05 + 0.30 * exploit + 0.30 * pv - 0.03 * deepFactor;
    if (canRaise && (wantsValueRaise || wantsBluffRaise)) {
      final r = raiseBy((0.5 * sizeScale + 0.6 * pv + 0.9 * geoBoost).clamp(0.33, 2.0));
      final risked = r.amount - p.currentBet;
      if (_deepCommitOk(p, risked, eq, deepFactor) &&
          _flushCommitOk(game, p, risked, eq)) {
        return r;
      }
      // Too committing to raise deep without the goods — just continue if priced.
    }
    // Facing a big bet deep, a marginal made hand shouldn't call off into likely
    // escalation on pure pot odds — demand a little extra to continue.
    // rRespect folds more to a passive player's bet (their aggression is rare,
    // so it's usually value).
    final callBar =
        potOdds + 0.06 * deepFactor * betFraction.clamp(0.0, 1.5) + rRespect;
    if (eq >= callBar &&
        _deepCommitOk(p, toCall, eq, deepFactor) &&
        _flushCommitOk(game, p, toCall, eq)) {
      return const GameAction.call();
    }
    return const GameAction.fold();
  }

  /// The commitment gate that keeps deep stacks from busting on non-premium
  /// holdings: the larger the fraction of a deep effective stack an action would
  /// put in this hand, the closer to the nuts the hand must be. Dormant at
  /// ≤100 BB ([deepFactor] 0) and for small commitments; near a full stack-off
  /// deep it demands ~0.95+ equity, so only genuine coolers get all the chips in
  /// — which is what makes big-field first-orbit bustouts rare.
  bool _deepCommitOk(Player p, int risked, double equity, double deepFactor) {
    if (deepFactor <= 0 || risked <= 0) return true;
    final effTotal = p.totalContributed + p.stack; // this hand's effective stack
    if (effTotal <= 0) return true;
    final commitFrac = ((p.totalContributed + risked) / effTotal).clamp(0.0, 1.0);
    if (commitFrac < 0.30) return true; // a modest commitment is always fine
    final bar = (0.53 + 0.50 * commitFrac * deepFactor).clamp(0.0, 0.98);
    return equity >= bar;
  }

  /// A disciplined player won't stack off with a **non-nut flush** into a big
  /// pot: on a flushing board a higher flush is exactly what heavy multiway
  /// action represents. Returns false to veto a large commit unless the hero's
  /// equity clears a bar that climbs with how dominated the flush could be (how
  /// many higher cards of the suit are still live) and with each extra opponent.
  /// A no-op for small commitments (peeling one card is fine) and for the nut
  /// flush (or non-flush hands). Pros only — amateurs keep the leak.
  bool _flushCommitOk(PokerGame game, Player p, int risked, double equity) {
    final sev = _overflushRisk(p.hole, game.board);
    if (sev <= 0) return true;
    final total = p.stack + p.currentBet;
    final commitFrac = total <= 0 ? 1.0 : risked / total;
    if (commitFrac < 0.35) return true; // small commit: a cheap peel is fine
    final mw = game.players.where((x) => x.inHand && !identical(x, p)).length;
    // Heads-up, a made flush is genuinely strong (it beats every non-flush), so
    // only the very worst holdings get braked. The domination risk really bites
    // **multiway**, where heavy action means someone very likely holds a higher
    // flush — which is exactly the spot a pro must not stack off a low flush.
    if (mw < 2 && sev < 0.75) return true;
    final bar = (0.60 + 0.22 * sev + 0.10 * (mw - 1)).clamp(0.0, 0.985);
    return equity >= bar;
  }

  /// How dominated the hero's made flush could be, in [0,1]: 0 = not a (plain)
  /// flush or already the nut flush; higher = more live higher cards of the
  /// flush suit a villain could be holding. Straight flushes and non-flush hands
  /// return 0 (they aren't out-flushed).
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
    // Ranks of the suit above the hero's best, not visible to the hero: a
    // villain could hold any of them for a better flush.
    var higherLive = 0;
    for (var r = 14; r > heroTop; r--) {
      if (!seen.contains(r)) higherLive++;
    }
    return (higherLive / 4).clamp(0.0, 1.0);
  }

  /// The single opponent this decision is most about: the bettor when facing a
  /// bet (largest committed opponent), else the opponent who will face our
  /// action. Returns their accumulated stats, or null with no read.
  PlayerStats? _representativeOpponent(PokerGame game, Player p, int toCall) {
    if (_reads == null) return null;
    final opps =
        game.players.where((x) => x.inHand && !identical(x, p)).toList();
    if (opps.isEmpty) return null;
    if (toCall > 0) {
      opps.sort((a, b) => b.currentBet.compareTo(a.currentBet));
    }
    return _reads.forSeat(opps.first.id);
  }
}
