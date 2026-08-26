import 'dart:math';

import 'package:monte/core/domain/ai/stack_context.dart';
import 'package:monte/core/domain/engine/bet_sizing.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

/// How large a first-in open-raise should be.
///
/// The preflop counterpart to [StackContext.fractionToReachSpr]: a *derived*
/// size rather than a constant. Before this, every preflop raise in every policy
/// came from `minRaiseTo + 0.5 × pot`, which preflop is `2 BB + 0.5 × 1.5 BB` —
/// **2.75 BB from every seat at every stack depth in every format**. A constant
/// wearing the costume of a calculation.
///
/// Worse, the one thing that moved it was pot size, and the biggest preflop
/// pot-size lever in this codebase is the big-blind ante, which is
/// tournament-only. So the bots opened *bigger* in tournaments (3.25 BB) than in
/// cash (2.75 BB), which is precisely backwards.
///
/// **There is deliberately no cash/tournament flag here.** The reason the two
/// formats size differently is not the format — it is that tournaments are
/// shallow and have antes while cash is deep and does not. Two players at 30 BB
/// with an ante should open the same whether it is a final table or a
/// short-stacked cash game, and a `bool isTournament` would get that wrong.
/// Model the physics; the format difference falls out. What genuinely *is*
/// tournament-specific — ICM, pay-jump laddering — already lives behind
/// `TournamentContext` and `IcmAdjustedDecider`.
class OpenSizing {
  const OpenSizing._();

  /// The pot, in big blinds, with no ante: the two blinds.
  static const noAnteDeadMoney = 1.5;

  /// Open-raise size in big blinds by effective stack depth, no ante, no
  /// limpers.
  ///
  /// Deep, you open larger: a big raise charges speculative hands a real price
  /// and builds a pot you have position and skill to play. Short, you open
  /// smaller: a 3-bet is a shove either way, so paying 3 BB to find that out is
  /// pure waste, and risking 3 to win 1.5 needs fold equity you do not have at
  /// 15 BB.
  ///
  /// Anchored to **live cash** convention rather than online: 3.5x at 100 BB,
  /// with tournament depths landing near 2.2x once the ante discount applies.
  /// Online solver sizing (2.0–2.5x at 100 BB) is a defensible alternative and
  /// would be this same list shifted down ~0.6 — a judgement about what the app
  /// should teach, not a fact, and made deliberately.
  ///
  /// **The deep tail is flatter than live convention, and it is load-bearing.**
  /// 200/400 BB sit at 3.7/3.9 rather than the 4.0/4.5 the curve wants, because
  /// `deep_stack_discipline_test` (WSOP Main Event level 1: 300 BB, no ante)
  /// bloated its 90th-percentile pot past the band at the larger values — a
  /// preflop pot compounds over three streets, so the deep open is multiplied,
  /// not added.
  ///
  /// That failure is a real limitation of this class's premise, not a tuning
  /// nuisance. The claim above is that format falls out of depth + antes; a
  /// deep *tournament* is the case where it does not, because tournament
  /// players open small at 300 BB for survival reasons that depth cannot see,
  /// and Main Event level 1 has no ante to mark it as a tournament. Survival is
  /// exactly what `TournamentContext` is for, so the principled fix is to let
  /// ladder pressure damp the deep end — not to keep shaving this list.
  ///
  /// Interpolated in **log** depth, because the interesting axis is doublings
  /// of stack, not chips: the step from 25 to 50 BB matters as much as 200 to
  /// 400.
  ///
  /// Parallel arrays rather than a map: Dart forbids `double` keys in a const
  /// map (they override `==`). [_depthAnchors] must stay ascending.
  static const _depthAnchors = <double>[15, 25, 50, 100, 200, 400];
  static const _sizeAnchors = <double>[2.2, 2.4, 2.9, 3.5, 3.7, 3.9];

  /// Big blinds shaved off the open per big blind of dead money above
  /// [noAnteDeadMoney].
  ///
  /// This is the ante term, and it is the *opposite sign* to the ante term in
  /// `OpenRanges`. More dead money means a steal risks less to win more, which
  /// widens the **range** (OpenRanges, correctly) and shrinks the **size**
  /// (here). A full big-blind ante takes about 0.4 BB off, turning a 2.6 BB cash
  /// open into the 2.2 BB that is standard with antes.
  static const _anteDiscountPerBb = 0.40;

  /// Added per limper. Each limper puts another big blind in the middle, so the
  /// raise has to be bigger to charge the same price relative to the pot — and
  /// it now has to get through more players.
  ///
  /// The old pot-fraction formula did produce *some* limper scaling as a side
  /// effect of the pot growing, but at half this rate, and by accident rather
  /// than as a decision.
  static const _perLimper = 1.0;

  /// At most this many limpers are charged for. Six-way limped pots do happen,
  /// but nobody opens to 9 BB.
  static const _maxLimpersCharged = 3;

  /// Hard bounds. A sub-2 BB "raise" is a min-raise the engine will reject
  /// anyway.
  ///
  /// The ceiling has to clear `deepest anchor + [_maxLimpersCharged]` — 3.9 + 3
  /// — or it silently truncates the limper term exactly where limped pots are
  /// most common. It was 6.0 while the anchors were online-sized, which was
  /// invisible then and wrong the moment they moved. A backstop against a
  /// runaway formula, not a poker opinion; the poker opinion lives in the
  /// anchors.
  static const _minBb = 2.0;
  static const _maxBb = 8.0;

  /// The no-ante, no-limper baseline open for a given effective stack depth.
  static double baseForDepth(double depthBb) {
    // NaN is the only genuinely meaningless input; an *infinite* depth is the
    // deepest case, not the shallowest, and lumping the two together under a
    // single `!isFinite` guard made an unbounded stack open the minimum.
    if (depthBb.isNaN) return baseForDepth(100);
    if (depthBb <= _depthAnchors.first) return _sizeAnchors.first;
    if (depthBb >= _depthAnchors.last) return _sizeAnchors.last;
    for (var i = 0; i + 1 < _depthAnchors.length; i++) {
      final lo = _depthAnchors[i], hi = _depthAnchors[i + 1];
      if (depthBb <= hi) {
        final t = (log(depthBb) - log(lo)) / (log(hi) - log(lo));
        return _sizeAnchors[i] + (_sizeAnchors[i + 1] - _sizeAnchors[i]) * t;
      }
    }
    return _sizeAnchors.last;
  }

  /// The size to open-raise **to**, in big blinds.
  ///
  /// [deadMoneyBb] is the blinds plus any antes, and must *exclude* limper
  /// chips — those are counted by [limpers], which is charged at a different
  /// rate. Folding them together would double-count and, worse, make limpers
  /// shrink the raise via the ante discount.
  ///
  /// [sizeScale] is personality, not situation — the same `riskPremiumCoefficient`
  /// clamp `ProfilePostflopPolicy._sizeFraction` already uses, extended here so
  /// preflop opens finally carry it too. Before this, every profile opened
  /// identically at a given depth: no signal to read because there was no
  /// variance to produce one, which is exactly what made preflop sizing
  /// "exploitable" in practice. Scales the amount *above* [_minBb], not the raw
  /// total, so a nit can never be scaled below a legal min-raise.
  static double openToBb({
    required double depthBb,
    double deadMoneyBb = noAnteDeadMoney,
    int limpers = 0,
    double sizeScale = 1.0,
  }) {
    var to = baseForDepth(depthBb);
    to -= _anteDiscountPerBb *
        (deadMoneyBb - noAnteDeadMoney).clamp(0.0, 3.0);
    to += _perLimper * limpers.clamp(0, _maxLimpersCharged);
    to = _minBb + (to - _minBb) * sizeScale;
    return to.clamp(_minBb, _maxBb);
  }

  /// How far a jittered open may drift from the computed size, in big blinds.
  ///
  /// Small and zero-mean by construction (`Random.nextDouble() - 0.5`): without
  /// this, the exact opened-to amount is a pure function of depth/position/dead
  /// money, which is a real tell — "they always open to exactly 2.8 BB here."
  /// Postflop already jitters its size fraction for the same reason.
  static const _jitterBb = 0.3;

  /// Live opponents who have limped: they have acted this round and are sitting
  /// at exactly one big blind.
  ///
  /// `hasActedThisRound` is what excludes the big blind itself, whose chips are
  /// forced and whose option is still live — it is dead money, not a limper.
  static int limperCount(PokerGame game, Player p) => game.players
      .where((x) =>
          !identical(x, p) &&
          !x.hasFolded &&
          x.hasActedThisRound &&
          x.currentBet == game.bigBlind)
      .length;

  /// The total chip amount to open-raise **to** for [p] in an unopened pot.
  ///
  /// Snapped to a human denomination and clamped legal, like every other sizing
  /// path. [random], if given, adds the small zero-mean jitter described at
  /// [_jitterBb]; omit it (as every existing deterministic test does) for the
  /// plain computed size.
  static int raiseToFor(
    PokerGame game,
    Player p, {
    double sizeScale = 1.0,
    Random? random,
  }) {
    final bb = game.bigBlind;
    if (bb <= 0) return game.minRaiseTo(p);

    final limpers = limperCount(game, p);
    // Everything in the middle that is not a limper's chips: blinds and antes.
    final deadBb = (game.pot / bb - limpers).clamp(0.0, 10.0);

    var toBb = openToBb(
      depthBb: StackContext.of(game, p).depthBb,
      deadMoneyBb: deadBb,
      limpers: limpers,
      sizeScale: sizeScale,
    );
    if (random != null) toBb += (random.nextDouble() - 0.5) * 2 * _jitterBb;
    return snapRaiseTo(game, p, (toBb * bb).round());
  }
}
