import 'dart:math';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

/// How much wider or tighter than baseline a seat should open an unopened pot.
///
/// Two separate effects, both of which were missing:
///
/// **Position.** Opening frequency is driven by how many players still have to
/// act behind you — every one of them is another chance to be raised or
/// outflopped. The old model ranked seats by *postflop* order, which puts the
/// small blind first and therefore treated it as the earliest, tightest seat.
/// Preflop the small blind is second to *last*, with a single opponent left to
/// get through, so it should be one of the widest. Measured before this fix,
/// open-when-folded-to was flat across the table — button 19%, small blind 15%,
/// under the gun 17% — against a real spread of roughly 15% early to 45% on the
/// button, and the result was a 9.3% walk rate.
///
/// **Dead money.** A steal risks a raise to win whatever is already out there.
/// With a big-blind ante that pot is far bigger — 2.5 BB rather than 1.5 BB —
/// so the same raise needs materially less fold equity to show a profit and the
/// correct opening range is genuinely wider. Nothing in the policies looked at
/// the pot at all, so antes changed opening behaviour by exactly zero.
class OpenRanges {
  const OpenRanges._();

  /// Extra **percentage points** of open-raising per position closer to the
  /// button, for a player who is *fully* position-aware. Additive, not
  /// multiplicative.
  ///
  /// Anchored to real 9/10-handed open-raise ranges: about 13% under the gun
  /// rising to about 42% on the button, which is six positions apart, so ~4.8
  /// points a seat. Each player then gets a share of that slope according to
  /// their `position_awareness` — the population average works out near three
  /// points a seat because most players are not fully aware, which is what the
  /// aggregate data shows.
  ///
  /// A straight line, not a curve. An exponential in players-behind gets the
  /// middle seats right and then compounds at the top: measured, it stepped
  /// +2, +2, +3, +5, +5, +5 from under the gun to the button, overshooting
  /// exactly where the ranges are widest and hardest to play well.
  static const _pointsPerPosition = 0.048;

  /// How much wider everyone opens as the table shrinks, **relative to
  /// six-max**.
  ///
  /// The first attempt at this fought the calibrator and lost.
  /// `ProfileCalibrator` is a closed loop: it tunes each profile's threshold
  /// until measured VPIP/PFR hits target, and it measures at **six-handed**.
  /// Any multiplier applied at six-max is simply cancelled by the loop
  /// re-converging, which is why nine-handed moved when the factor could not
  /// have touched it and why the calibration gate broke at 17.4% PFR against a
  /// required 18.0%.
  ///
  /// So the curve is pinned at 1.0 for six-handed *and* full ring, and only
  /// deviates below six. That leaves the calibrated band untouched by
  /// construction and confines the change to table sizes nothing calibrates
  /// against — which is exactly where the bug lives, since a profile was opening
  /// 26% heads-up where the charts say 80%, and getting *tighter* as seats
  /// emptied because the positional model is mean-zero across the table.
  ///
  /// A steal wins the blinds when everyone behind folds, and that probability
  /// compounds with each player left to act, so removing seats widens the
  /// correct range faster than linearly.
  ///
  /// **A first stab, deliberately.** These are reasoned rather than measured,
  /// and the honest way to dial them in is a duplicate-match gate at each table
  /// size. Until that exists, treat short-handed opening frequency as
  /// approximate.
  static double tableFactor(int players) {
    if (players >= 6) return 1.0;
    if (players <= 2) return 2.6;
    const anchors = {6: 1.0, 5: 1.15, 4: 1.35, 3: 1.7, 2: 2.6};
    final lo = anchors.keys.where((k) => k <= players).reduce(max);
    final hi = anchors.keys.where((k) => k >= players).reduce(min);
    if (lo == hi) return anchors[lo]!;
    final t = (players - lo) / (hi - lo);
    return anchors[lo]! + (anchors[hi]! - anchors[lo]!) * t;
  }

  /// How much more often a player open-raises than their headline PFR suggests.
  ///
  /// PFR counts raises against every hand *dealt*; an open-raise can only happen
  /// on the far rarer occasions the pot is folded to you, and in those spots you
  /// raise much more freely. Treating a 20% PFR as a 20% opening frequency put
  /// the whole curve a third too low — under the gun landed near 5% against a
  /// real 12–14%. For 9-handed play the two stats sit about 1.4x apart.
  static const _rfiOverPfr = 1.4;

  /// Points taken back off the small blind. It has the fewest players left to
  /// act, which by the rule above would make it the widest seat at the table —
  /// but it is out of position for the entire hand afterwards, so real charts
  /// put it a step below the button rather than above it.
  static const _outOfPositionPoints = 0.05;

  /// A note on pushing the button wider still.
  ///
  /// Published charts put the button nearer 40–45%; this model lands it around
  /// 32–34% with antes. Forcing the chart number by hand cost the pro field real
  /// money against a recreational opponent — at a 1.22x button premium a
  /// station went from −8 to +12…+20 bb/100 against a pro field. That is a fact
  /// about poker rather than a bug: a wide steal is only profitable when the
  /// players behind actually fold, and these pros fold *postflop*, so opening
  /// wider and then giving up is how a station gets paid. Widening therefore
  /// belongs where it is conditional on a read — `ProfilePolicy` already loosens
  /// its opening cut against blinds with a high measured `foldBlindStealRate` —
  /// rather than applied blind from a chart.

  /// The pot, in big blinds, that a first-in raiser is playing for when there is
  /// no ante: the two blinds.
  static const _noAnteDeadMoney = 1.5;

  /// Live opponents who still have to act behind [p] this round.
  ///
  /// Only meaningful for an unopened pot, where everyone before us has folded —
  /// then the players still in the hand after us are exactly the ones left to
  /// act.
  static int playersBehind(PokerGame game, Player p) {
    final n = game.players.length;
    final hero = game.players.indexOf(p);
    if (hero < 0) return 0;
    var behind = 0;
    for (var k = 1; k < n; k++) {
      final x = game.players[(hero + k) % n];
      if (x.inHand && !x.hasFolded) behind++;
    }
    return behind;
  }

  /// The multiplier to apply to a profile's baseline opening frequency.
  ///
  /// **Normalised to average 1.0 across the table**, so a player's overall
  /// VPIP/PFR still lands on its calibrated target — this redistributes
  /// aggression across seats rather than inventing more of it. The one thing
  /// that legitimately raises the average is [deadMoney] above the no-ante
  /// baseline, because antes really do widen everybody's ranges.
  ///
  /// [positionalProficiency] is the `Positional_Warfare` characteristic, which
  /// now amplifies an effect that applies to everyone rather than being the only
  /// thing that switches it on.
  /// The opening frequency for this seat, given a player's baseline [base]
  /// (their overall PFR target).
  ///
  /// The positional adjustment is **mean-zero across the table**, so a player's
  /// overall VPIP/PFR still lands on its calibrated target — this redistributes
  /// aggression between seats rather than inventing more of it. The one thing
  /// that legitimately raises the average is [deadMoneyBb] above the no-ante
  /// baseline, because antes really do widen everybody's ranges.
  ///
  /// [positionalProficiency] is the `Positional_Warfare` characteristic, which
  /// now sharpens an effect that applies to everyone rather than being the only
  /// thing that switches it on.
  static double openFrequency({
    required double base,
    required int playersBehind,
    required int tableSize,
    required bool isSmallBlind,
    required double deadMoneyBb,
    double positionAwareness = 1.0,
    double positionalProficiency = 0,
  }) =>
      (base * _rfiOverPfr * tableFactor(tableSize) +
              positionalDelta(
                playersBehind: playersBehind,
                tableSize: tableSize,
                isSmallBlind: isSmallBlind,
                deadMoneyBb: deadMoneyBb,
                positionAwareness: positionAwareness,
                positionalProficiency: positionalProficiency,
              ))
          .clamp(0.02, 0.95);

  /// The mean-zero positional adjustment, in fractions of hands (0.03 = three
  /// percentage points).
  static double positionalDelta({
    required int playersBehind,
    required int tableSize,
    required bool isSmallBlind,
    required double deadMoneyBb,
    double positionAwareness = 1.0,
    double positionalProficiency = 0,
  }) {
    if (tableSize < 2 || playersBehind < 1) return 0;

    // Position index: 0 is the earliest seat that can face an unopened pot,
    // rising by one for every seat closer to the button. The small-blind
    // correction lives *inside* the function being centred, since applying it
    // afterwards would drag the table mean off zero and quietly tighten
    // everyone.
    double points(int behind, bool sb) {
      final index = (tableSize - 1) - behind;
      var pts = _pointsPerPosition * index;
      if (sb || behind <= 1) pts -= _outOfPositionPoints;
      return pts;
    }

    final seats = tableSize - 1;
    var sum = 0.0;
    for (var b = 1; b <= seats; b++) {
      sum += points(b, b <= 1);
    }
    var delta = points(playersBehind, isSmallBlind) - sum / seats;

    // How much of that slope this player actually expresses. The full curve
    // belongs to someone completely position-aware; a player who barely notices
    // where they are sitting plays close to the same range from every seat.
    // Scaling a mean-zero delta leaves it mean-zero, so calibration survives at
    // any awareness.
    delta *= positionAwareness.clamp(0.0, 1.0);

    // The characteristic sharpens the tilt further — a positional specialist is
    // more extreme than even a fully aware player.
    if (positionalProficiency > 0) {
      delta *= 1 + 0.5 * positionalProficiency.clamp(0.0, 1.0);
    }

    // Dead money: more in the middle means a steal needs less fold equity, so
    // every seat opens a little wider. Bounded so a huge ante cannot open the
    // range without limit.
    final extra = (deadMoneyBb - _noAnteDeadMoney).clamp(0.0, 3.0);
    return delta + 0.04 * (extra / _noAnteDeadMoney);
  }

  /// Convenience: the opening frequency for [p] facing an unopened pot.
  static double forSeat(
    PokerGame game,
    Player p, {
    required double base,
    double positionAwareness = 1.0,
    double positionalProficiency = 0,
  }) {
    final n = game.players.length;
    final sbIndex = n == 2 ? game.buttonIndex : (game.buttonIndex + 1) % n;
    final bb = game.bigBlind;
    return openFrequency(
      base: base,
      playersBehind: playersBehind(game, p),
      tableSize: n,
      isSmallBlind: game.players.indexOf(p) == sbIndex,
      deadMoneyBb: bb <= 0 ? _noAnteDeadMoney : game.pot / bb,
      positionAwareness: positionAwareness,
      positionalProficiency: positionalProficiency,
    );
  }
}
