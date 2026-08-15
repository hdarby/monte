import 'dart:math';

import 'package:monte/core/domain/ai/hand_range.dart';
import 'package:monte/core/domain/ai/opponent_reads.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_stats.dart';
import 'package:monte/core/domain/ai/postflop_equity.dart';
import 'package:monte/core/domain/ai/stack_context.dart';
import 'package:monte/core/domain/ai/trigger_context.dart';
import 'package:monte/core/domain/ai/trigger_observer.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/bet_snap.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/board_texture.dart';
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
  ProfilePostflopPolicy(
    this.profile, {
    Random? random,
    OpponentReads? reads,
    TriggerObserver? triggers,
  }) : _random = random ?? Random() {
    _reads = reads;
    _triggers = triggers;
  }

  final PlayerProfile profile;
  final Random _random;

  /// Accumulated reads on the opponents (null = no data / GTO seat).
  late final OpponentReads? _reads;

  /// Records signature moves when they fire, so they can be verified rather
  /// than taken on faith. Null in production.
  late final TriggerObserver? _triggers;

  void _fired(String id, Player p) => _triggers?.onFired(id, p.id);

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
    // Depth and stack-to-pot ratio both come from the one shared reader; see
    // [StackContext] for why they are different numbers and why depth must be
    // taken from the start-of-hand stacks.
    final ctx = StackContext.of(game, p);
    final deepFactor = ctx.depthPressure;

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
    var rSuspect = 0.0; // look up a player who bets too often to be value-only
    final st = _representativeOpponent(game, p, toCall);
    if (st != null && st.established) {
      final w = (exploit * st.confidence).clamp(0.0, 1.0);
      // Blend the c-bet-specific and the broad postflop fold-to-bet signals: a
      // player who folds to aggression generally (not just c-bets) is a prime
      // bluff target; one who shows down weak pays off thin value.
      final foldy = (0.6 * (st.foldToCbetRate - 0.45) +
          0.4 * (st.foldToBetRate - 0.42));
      rBluffMore = (foldy * 2.0 * w).clamp(-0.30, 0.30);
      // Station read from both calling tendency and a low won-at-showdown.
      final station = (-foldy) + 0.5 * (0.5 - st.wonAtShowdownRate);
      rValueThin = (station * 0.8 * w).clamp(0.0, 0.15);
      if (toCall > 0) {
        final passive = (1.0 - st.aggressionFactor).clamp(0.0, 1.0);
        rRespect = (passive * 0.12 * w).clamp(0.0, 0.12);
        // The mirror image, and the *only* licence to hero-call: an opponent
        // betting and raising far more often than they call cannot have value
        // every time. Zero until the read is established, so a bot with no
        // information never talks itself into a call.
        final pushy = (st.aggressionFactor - 1.0).clamp(0.0, 1.0);
        rSuspect = (pushy * 0.30 * w).clamp(0.0, 0.30);
      }
    }

    // Signature moves are written against this shared predicate vocabulary.
    final tc = TriggerContext.of(game, p, profile, villainStats: st);

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
    // Bet size sets how much of the betting range is air. Minimum-defence gives
    // the balanced number for the size the villain chose (½ pot ⇒ 25%, pot ⇒
    // 33%), but real pools under-bluff big sizings, so overbets damp toward
    // value — which is what makes a 3×-pot jam an easy fold for a bluff-catcher.
    // rRespect folds out bluffs entirely against a passive opponent whose bets
    // are almost always value (it used to be a bump on the call bar; it belongs
    // here, in the read, and applying it in both places double-counted it).
    final mdf = betFraction / (1 + 2 * betFraction);
    final bigBetDamp = 1 - 0.5 * ((betFraction - 1.0) / 2.0).clamp(0.0, 1.0);
    final assumedBluffs = (mdf * bigBetDamp - rRespect).clamp(0.02, 0.45);
    // No `betFraction` on narrowedBy any more: size is expressed through
    // `assumedBluffs` below, and narrowing on it as well counted it twice.
    var range = HandRange.top(perceivedTop, dead: dead).narrowedBy(
      raiseCount: raises,
      street: game.round,
    );
    if (toCall > 0) {
      // Facing a bet, read the villain for a *betting* range, not a continuing
      // range — the fix that stops the bot beating a pile of unpaired big cards
      // with third pair and calling on the price.
      // Size narrows the range as well as its bluff share. A normal bet is made
      // with a wide range; an overbet is a narrow, value-heavy one, so the whole
      // betting range collapses toward the top as the size grows. Without this a
      // bluff-catcher prices in against a 3×-pot jam, because the extra bluffs
      // that minimum-defence credits an overbet with cancel out its extra value.
      final width = (0.85 / (1 + 0.5 * max(0.0, betFraction - 1.0)))
          .clamp(0.35, 0.85);
      range = range.polarisedOn(
        game.board,
        bluffFraction: assumedBluffs,
        betRangeFraction: width,
      );
    }
    final eq = PostflopEquity.equityMultiway(
      p.hole,
      game.board,
      range,
      opponents: liveOpp,
      iterations: equityIters,
      random: _random,
    );
    final isDraw = eq >= 0.32 && eq <= 0.55;

    // Board texture drives sizing (see [_sizeFraction]) — the single biggest
    // reason a real player's bets vary rather than sitting on one number.
    final texture = BoardTexture.maybeOf(game.board);

    // Leverage pressure: some pros hunt for spots to apply maximum pressure —
    // when the pot is heads-up, or when a bet can set an opponent all-in to
    // continue. It ramps aggression and bluffs and sizes up toward the
    // opponent's stack (a jam threat), scaled by the characteristic's proficiency.
    final lev = profile.proficiencyOf('Leverage_Pressure');
    final minOppStack =
        liveOpps.isEmpty ? 1 << 30 : liveOpps.map((x) => x.stack).reduce(min);
    final canJam = minOppStack <= game.pot; // a pot-ish bet puts them all-in
    // Leverage is a *spot*, not a default. It used to fire on `liveCount == 2`
    // alone — but heads-up is the ordinary state of a poker hand, not a special
    // one, so every leverage pro ramped sizing and bluffs on almost every pot.
    // That is the shove-fest: pressure has to mean a bet that genuinely threatens
    // a stack. And don't ramp when deep unless the hand wants stacks in anyway.
    final pv = (lev > 0 && canJam && (deepFactor < 0.5 || eq > 0.80)) ? lev : 0.0;

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
      // Deep, a bluff is an invitation to be raised off the hand or to build a
      // pot with the worst of it, so real players bluff less the deeper they
      // are. This is the other half of the pot-bloat fix: without it, smaller
      // sizings just mean more streets of betting.
      final bluffChance = ((0.10 + 0.35 * exploit + 0.30 * pv + 0.30 * sr) *
                  ((1 - eq) * 0.6 + (isDraw ? 0.4 : 0.0)) +
              0.4 * rBluffMore) *
          (1 - 0.45 * deepFactor);
      final wantsBluff = _random.nextDouble() < bluffChance;
      // Float and take it away: we called their flop bet in position with
      // little, they have surrendered the turn, so we take it. Fires on air --
      // with a real hand the ordinary value logic already bets.
      final float = profile.proficiencyOf('Float_And_Take_Away');
      if (float > 0 &&
          tc.onTurn &&
          tc.calledFlop &&
          tc.inPosition &&
          tc.headsUp &&
          eq < 0.55 &&
          p.stack > bb &&
          _random.nextDouble() < 0.65 * float) {
        _fired('Float_And_Take_Away', p);
        final b = betBy((0.55 * sizeScale).clamp(0.33, 0.75));
        final risked = b.amount - p.currentBet;
        if (_commitOk(p, risked, eq, deepFactor, aggressive: true)) return b;
      }

      // Slow-play trap: with a genuine monster, take the passive line and let
      // them catch up or bluff into it. A *line* change, not a sizing one --
      // which is precisely what `action_modifier` multipliers could never say.
      // Restricted to hands strong enough that giving a free card is cheap, and
      // to earlier streets, so it never becomes "check the river and win
      // nothing".
      final trap = profile.proficiencyOf('Slow_Play_Trap');
      if (trap > 0 &&
          !tc.onRiver &&
          wantsValue &&
          eq > 0.86 &&
          tc.madeAtLeast(HandRank.threeOfAKind) &&
          _random.nextDouble() < 0.55 * trap) {
        _fired('Slow_Play_Trap', p);
        return const GameAction.check();
      }

      if ((wantsValue || wantsBluff) && p.stack > bb) {
        // Cap the size at whatever still arrives at the SPR this hand deserves.
        // A pure bluff is sized as a marginal hand, not as the value hand it is
        // representing — betting big with air is how a deep pot gets built with
        // the worst of it.
        final sprCap = ctx.fractionToReachSpr(
          _targetSpr(wantsValue ? eq : min(eq, 0.5), ctx.spr),
        );
        // Pressure (jam threat) and geometric overbets both size up; the overbet
        // only fires with a nut advantage on a later street.
        final b = betBy(
          _sizeFraction(
            texture: texture,
            // A bluff or the near-nuts is polarised; middling value is merged.
            polarised: !wantsValue || eq > 0.85,
            thinValue: wantsValue && eq < 0.72,
            opponents: liveOpp,
            sizeScale: sizeScale,
            pressure: pv,
            geoBoost: geoBoost,
            cap: sprCap,
          ),
        );
        final risked = b.amount - p.currentBet;
        if (_commitOk(p, risked, eq, deepFactor, aggressive: true) &&
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
    // A semibluff needs cards to come. On the river the `isDraw` equity band
    // (0.32–0.55) contains no draws at all — just weak made hands — so raising
    // it was a pure punt, and it drove a 15.6% river raise rate in the tuning
    // log. The river keeps only a token bluff-raise, and only where a read says
    // the opponent folds too much ([rBluffMore]): a move worth making, not a
    // coin-flip with a stack. Turn semibluffs are also trimmed — they are real
    // (there is a card to come) but they were firing far too often.
    final onRiver = game.round == BettingRound.river;
    final wantsBluffRaise = onRiver
        ? eq < 0.35 &&
            _random.nextDouble() <
                (0.005 + 0.5 * rBluffMore.clamp(0.0, 0.30)).clamp(0.0, 0.10)
        : isDraw &&
            _random.nextDouble() <
                (0.04 + 0.22 * exploit + 0.22 * pv) * (1 - 0.55 * deepFactor);
    if (canRaise && (wantsValueRaise || wantsBluffRaise)) {
      final raiseCap = ctx.fractionToReachSpr(
        _targetSpr(wantsValueRaise ? eq : min(eq, 0.5), ctx.spr),
      );
      final r = raiseBy(
        _sizeFraction(
          texture: texture,
          polarised: wantsBluffRaise || eq > 0.85,
          thinValue: wantsValueRaise && eq < 0.80,
          opponents: liveOpp,
          sizeScale: sizeScale,
          pressure: pv,
          geoBoost: geoBoost,
          cap: raiseCap,
        ),
      );
      final risked = r.amount - p.currentBet;
      if (_commitOk(p, risked, eq, deepFactor, aggressive: true) &&
          _flushCommitOk(game, p, risked, eq)) {
        return r;
      }
      // Too committing to raise deep without the goods — just continue if priced.
    }
    // Facing a big bet deep, a marginal made hand shouldn't call off into likely
    // escalation on pure pot odds — demand a little extra to continue. (The
    // passive-opponent read now lives in `assumedBluffs`, not here.)
    // The river has no cards to come and no implied odds, so a bluff-catch that
    // is merely break-even at the price is a coin-flip for chips — and in a
    // tournament a negative-ICM one. Demand a real margin over the price to call
    // the end. Without this a bluff-catcher sits exactly at indifference by
    // construction and a rounding error decides the hand, which is what the
    // 28.9% fold-to-river-bet in the tuning log actually was.
    final riverMargin = onRiver ? 0.02 : 0.0;
    var callBar =
        potOdds + riverMargin + 0.06 * deepFactor * betFraction.clamp(0.0, 1.5);

    // Underbluff exploit: recreational players essentially do not bluff the
    // river, so a bluff-catcher facing one is drawing to a hand they rarely
    // have. Demand materially more to call. Read-gated, so it never fires on a
    // hunch.
    final baseBar = callBar;
    final underbluff = profile.proficiencyOf('Underbluff_Exploit');
    if (underbluff > 0 && onRiver && tc.villainIsRecreational) {
      callBar += 0.18 * underbluff;
    }

    // Sticky showdown: they simply will not fold a made hand. Lowers the bar
    // once top pair or better is in hand -- and *only* then, so it produces
    // paying off the river rather than calling with air. The commitment gates
    // below are untouched: sticky means one more crying call, not stacking off
    // 300 BB deep.
    final sticky = profile.proficiencyOf('Sticky_Showdown');
    if (sticky > 0 && (tc.hasTopPair || tc.madeAtLeast(HandRank.twoPair))) {
      callBar -= 0.14 * sticky;
    }

    // Record only when the move actually *changed the decision*, not merely
    // when its condition held. A counter that ticks every time a bar shifts by
    // a hair says nothing about whether the move matters.
    if (callBar < baseBar && eq >= callBar && eq < baseBar) {
      _fired('Sticky_Showdown', p);
    } else if (callBar > baseBar && eq < callBar && eq >= baseBar) {
      _fired('Underbluff_Exploit', p);
    }

    if (eq >= callBar &&
        _commitOk(p, toCall, eq, deepFactor) &&
        _flushCommitOk(game, p, toCall, eq)) {
      return const GameAction.call();
    }
    // Hero call. Against a balanced betting range a bluff-catcher is close to
    // indifferent by construction — equity lands near the price — so only a
    // *read* can break the tie in favour of calling. It is therefore driven
    // almost entirely by [rSuspect], which is zero until this opponent's
    // aggression is established: a bot with no information folds instead of
    // guessing, because a hero call without exploit data is just a punt.
    // Bounded to the sliver just below the bar and still commitment-gated, so
    // it can never be the call that costs a stack.
    final heroCallChance = (0.01 + rSuspect).clamp(0.0, 0.30);
    if (eq >= callBar - 0.05 &&
        _random.nextDouble() < heroCallChance &&
        _commitOk(p, toCall, eq, deepFactor) &&
        _flushCommitOk(game, p, toCall, eq)) {
      return const GameAction.call();
    }
    return const GameAction.fold();
  }

  /// The commitment gate that stops a bot playing a whole stack off on a
  /// pot-odds call: the larger the fraction of the effective stack an action
  /// would put in this hand, the stronger the hand must be. Pot odds price
  /// *this* call, not the stack-off it usually leads to — this is what supplies
  /// the difference.
  ///
  /// It used to be dormant at ≤100 BB ([deepFactor] 0) — i.e. switched off for
  /// the whole of tournament play, which is exactly where the bustouts were
  /// coming from. Now a shallow floor bites at every depth (a full stack-off
  /// needs ~0.60 equity), and [deepFactor] only *steepens* it when deep, so the
  /// previously-tuned deep behaviour is unchanged.
  /// [aggressive] marks a bet or raise rather than a call. It matters: a bet can
  /// win the pot uncontested, so raw hand equity understates it, and applying
  /// the shallow floor to aggression would wipe out short-stack bluffing and
  /// leave nothing but nit-shoving. Aggression therefore keeps the original
  /// deep-only discipline; only *calls* — which have no fold equity to fall back
  /// on — face the new floor. Calling off a stack is what busts players.
  bool _commitOk(
    Player p,
    int risked,
    double equity,
    double deepFactor, {
    bool aggressive = false,
  }) {
    if (risked <= 0) return true;
    final effTotal = p.totalContributed + p.stack; // this hand's effective stack
    if (effTotal <= 0) return true;
    final commitFrac = ((p.totalContributed + risked) / effTotal).clamp(0.0, 1.0);
    if (commitFrac < 0.30) return true; // a modest commitment is always fine
    final shallow = aggressive ? 0.0 : 0.30 + 0.30 * commitFrac;
    final deep = deepFactor <= 0 ? 0.0 : 0.53 + 0.50 * commitFrac * deepFactor;
    final bar = max(shallow, deep).clamp(0.0, 0.98);
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


  /// The stack-to-pot ratio a hand of this [equity] should be *aiming to face*
  /// when the last of the money goes in, given the [current] SPR.
  ///
  /// This is the deep-stack discipline in one function, and the target has to be
  /// **proportional** rather than absolute. An absolute target misbehaves at both
  /// ends: "arrive at SPR 3" is a normal half-pot bet from SPR 10, but from SPR
  /// 40 it demands an enormous one — the exact opposite of playing small when
  /// deep. Expressed as a share of the SPR you already have, one pair keeps
  /// better than half of it (so it never gets committed), while the near-nuts
  /// keeps none (a stack-off).
  static double _targetSpr(double equity, double current) {
    final retain = equity >= 0.88
        ? 0.00 // get it in
        : equity >= 0.78
            ? 0.10
            : equity >= 0.68
                ? 0.20
                : equity >= 0.58
                    ? 0.35
                    : 0.55; // marginal or a bluff: stay uncommitted
    if (!current.isFinite) return retain <= 0 ? 0 : 1e6;
    return current * retain;
  }

  /// Picks a bet size as a fraction of the pot.
  ///
  /// Real players do not bet one size. The size is driven by *why* they are
  /// betting and *what the board looks like*:
  ///
  /// - **Static / dry** boards: small. Nothing is getting outdrawn, so the goal
  ///   is thin value and keeping worse hands in — a third to a half pot.
  /// - **Dynamic / wet** boards: large. Equity denial is worth real money, so
  ///   charge the draws — two-thirds to a full pot.
  /// - **Polarised** holdings (the near-nuts, or a pure bluff) size up; **merged**
  ///   thin-value hands size down, because they want calls from worse.
  /// - **Multiway** sizes up: more players means more equity to deny and a
  ///   greater chance somebody has a real hand.
  ///
  /// A little jitter keeps the sizing from being a readable tell. The profile's
  /// [sizeScale] (its risk premium) still tilts the whole distribution, so an
  /// aggressive personality genuinely bets bigger than a passive one.
  double _sizeFraction({
    required BoardTexture? texture,
    required bool polarised,
    required bool thinValue,
    required int opponents,
    required double sizeScale,
    required double pressure,
    required double geoBoost,
    required double cap,
  }) {
    var f = 0.52;

    if (texture != null) {
      if (texture.isStatic) f -= 0.16;
      if (texture.isDynamic) f += 0.16;
      if (texture.isDry) f -= 0.08;
      if (texture.isWet) f += 0.10;
      // A made flush out there polarises the betting range hard.
      if (texture.isMonochrome) f += 0.06;
      // Paired boards are cheap to represent, so bets run smaller.
      if (texture.isPaired) f -= 0.05;
    }

    if (polarised) f += 0.20;
    if (thinValue) f -= 0.12;

    // Each extra opponent beyond the first adds protection value.
    f += 0.07 * (opponents - 1).clamp(0, 3);

    f *= sizeScale;
    // Pressure sizes up, but modestly. A big bet now folds out far more of the
    // opponent's range (see `polarisedOn`), so ramping toward a jam on every
    // pressure spot *costs* value — the money comes from sizes that get called.
    // The geometric overbet still reaches the top of the range, but it needs a
    // genuine nut advantage to fire.
    f += 0.35 * pressure + 0.9 * geoBoost;

    // ±0.06 of jitter so the size itself carries no information.
    f += (_random.nextDouble() - 0.5) * 0.12;

    // The SPR ceiling wins over the texture-driven size, but never squeezes a
    // bet below a quarter pot — below that it stops being a bet at all, and the
    // hand should simply check.
    f = min(f, max(cap, 0.25));
    return f.clamp(0.25, 2.0);
  }

}
