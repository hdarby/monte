import 'dart:math';

import 'package:monte/core/domain/ai/background_quality.dart';
import 'package:monte/core/domain/ai/hand_range.dart';
import 'package:monte/core/domain/ai/heuristic_postflop_evaluator.dart';
import 'package:monte/core/domain/ai/mental_state.dart';
import 'package:monte/core/domain/ai/opponent_reads.dart';
import 'package:monte/core/domain/ai/personality_post_processor.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_stats.dart';
import 'package:monte/core/domain/ai/postflop_equity.dart';
import 'package:monte/core/domain/ai/postflop_search_evaluator.dart';
import 'package:monte/core/domain/ai/stack_context.dart';
import 'package:monte/core/domain/ai/trigger_context.dart';
import 'package:monte/core/domain/ai/trigger_observer.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/board_texture.dart';
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
  ProfilePostflopPolicy(
    this.profile, {
    Random? random,
    OpponentReads? reads,
    TriggerObserver? triggers,
    MentalReads? mental,
    int Function()? tableCountProvider,
    int Function()? equityTableCountProvider,
  }) : _random = random ?? Random() {
    _reads = reads;
    _triggers = triggers;
    _mental = mental;
    _evaluator = HeuristicPostflopEvaluator(_random);
    _searchEvaluator = PostflopSearchEvaluator(_random, profile);
    _postProcessor = PersonalityPostProcessor(_random);
    _tableCountProvider = tableCountProvider;
    _equityTableCountProvider = equityTableCountProvider;
  }

  final PlayerProfile profile;
  final Random _random;
  late final HeuristicPostflopEvaluator _evaluator;
  late final PostflopSearchEvaluator _searchEvaluator;
  late final PersonalityPostProcessor _postProcessor;

  /// Reports the number of tables still live in the tournament this seat
  /// belongs to (null outside a tournament, or for the cash table). Read at
  /// decision time, not captured at construction, so the search cutover
  /// activates the moment the field consolidates to the true final table —
  /// including via `TournamentController._finishHeadless`'s resolve-below-72
  /// branch, which reuses these same constructed deciders.
  late final int Function()? _tableCountProvider;

  /// Separate from [_tableCountProvider] on purpose: that one gates the
  /// search-evaluator cutover ("is this the true final table?", a fixed
  /// meaning that must not shift). This one drives the equity-iteration
  /// scale (see [equityIterationScale]) and reports `1` whenever *this seat*
  /// is currently seated at the human's own live table, regardless of how
  /// many tables remain in the tournament overall — so the opponents you're
  /// actually playing against always reason at full resolution, and only
  /// seats off at background tables get the cheaper scaled-down estimate.
  /// Falls back to [_tableCountProvider] when not supplied (cash table,
  /// tests) so those callers are unaffected.
  late final int Function()? _equityTableCountProvider;

  /// Locked decision: the search-backed postflop evaluator only ever plays
  /// the true final table.
  static const int finalTableCutoff = 1;

  /// Accumulated reads on the opponents (null = no data / GTO seat).
  late final OpponentReads? _reads;

  /// Records signature moves when they fire, so they can be verified rather
  /// than taken on faith. Null in production.
  late final TriggerObserver? _triggers;

  /// How rattled each seat is (see [MentalReads]). Null = nobody tilts.
  late final MentalReads? _mental;

  void _fired(String id, Player p, BettingRound street) {
    _triggers?.onFired(id, p.id, street);
  }

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
    final scale = equityIterationScale(
        (_equityTableCountProvider ?? _tableCountProvider)?.call());
    final equityIters =
        (_equityIterations * (1 + soul) * scale).round().clamp(20, 1 << 30);
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
    final checkRaiseProf = profile.proficiencyOf('Check_Raise_Merchant');
    final geo = profile.proficiencyOf('Geometric_Overbet_Execution');
    final laterStreet =
        game.round == BettingRound.turn || game.round == BettingRound.river;
    final geoBoost = (geo > 0 && laterStreet && eq > 0.80) ? geo : 0.0;

    // Locked scope: preflop always uses the heuristic percentile-cutoff
    // system; only postflop swaps evaluators, and only at the true final
    // table (`tableCount <= 1`) — everywhere else this reads as `false`
    // (`tableCountProvider` null outside a tournament).
    final atFinalTable =
        (_tableCountProvider?.call() ?? finalTableCutoff + 1) <=
            finalTableCutoff;

    final evaluator = atFinalTable
        ? _searchEvaluator.decide
        : _evaluator.decide;
    final result = evaluator(
      game: game,
      p: p,
      profile: profile,
      ctx: ctx,
      tc: tc,
      mental: _mental,
      eq: eq,
      isDraw: isDraw,
      texture: texture,
      pv: pv,
      sr: sr,
      geoBoost: geoBoost,
      checkRaiseProf: checkRaiseProf,
      exploit: exploit,
      sizeScale: sizeScale,
      deepFactor: deepFactor,
      rValueThin: rValueThin,
      rBluffMore: rBluffMore,
      rSuspect: rSuspect,
      liveOpp: liveOpp,
      toCall: toCall,
      bb: bb,
      canRaise: canRaise,
      betFraction: betFraction,
      inPosition: inPosition,
    );
    // Only the two genuine two-live-candidate spots (call vs. fold near
    // `callBar`; bet vs. check near the value/bluff threshold) carry a
    // runnerUp — mix is a no-op everywhere else.
    final candidate = _postProcessor.mix(
      result.chosen,
      result.runnerUp,
      marginScale: atFinalTable
          ? PersonalityPostProcessor.closeDecisionMarginSearch
          : null,
    );
    _postProcessor.fireTriggers(candidate, (id) => _fired(id, p, game.round));
    return candidate.action;
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
