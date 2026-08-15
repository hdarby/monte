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

  /// Per-street decay in opening frequency for each extra player left to act.
  /// 0.85 gives roughly a 3.7× spread between the small blind and under the
  /// gun, against about 3× in published charts.
  static const _decayPerPlayer = 0.85;

  /// The small blind opens wide because only one player is left — but it is out
  /// of position for the whole hand afterwards, so it trails the button. Real
  /// charts put it at roughly 40% against the button's 45%.
  static const _outOfPositionPenalty = 0.76;

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
  static double openMultiplier({
    required int playersBehind,
    required int tableSize,
    required bool isSmallBlind,
    required double deadMoneyBb,
    double positionalProficiency = 0,
  }) {
    if (tableSize < 2 || playersBehind < 1) return 1.0;

    // Facing an unopened pot, exactly one seat has a single player behind it —
    // the small blind — so the out-of-position penalty belongs *inside* the
    // function being normalised. Applying it afterwards would drag the table
    // mean below 1 and quietly tighten everyone.
    double raw(int behind, bool sb) {
      var v = pow(_decayPerPlayer, behind - 1).toDouble();
      if (sb || behind <= 1) v *= _outOfPositionPenalty;
      return v;
    }

    // Normalise over every seat that can face an unopened pot, so the mean
    // multiplier is 1 and the profile's calibration survives.
    final seats = tableSize - 1;
    var sum = 0.0;
    for (var b = 1; b <= seats; b++) {
      sum += raw(b, b <= 1);
    }
    final mean = sum / seats;
    var m = mean <= 0 ? 1.0 : raw(playersBehind, isSmallBlind) / mean;

    // The characteristic sharpens the tilt without changing its average.
    if (positionalProficiency > 0) {
      m = 1 + (m - 1) * (1 + 0.5 * positionalProficiency.clamp(0.0, 1.0));
    }

    // Dead money: more in the middle means a steal needs less fold equity, so
    // the range widens. Capped so a huge ante cannot open the range without
    // limit.
    final extra = (deadMoneyBb - _noAnteDeadMoney).clamp(0.0, 3.0);
    m *= 1 + 0.30 * (extra / _noAnteDeadMoney);

    return m.clamp(0.15, 4.0);
  }

  /// Convenience: the multiplier for [p] facing an unopened pot in [game].
  static double forSeat(
    PokerGame game,
    Player p, {
    double positionalProficiency = 0,
  }) {
    final n = game.players.length;
    final sbIndex = n == 2
        ? game.buttonIndex
        : (game.buttonIndex + 1) % n;
    final bb = game.bigBlind;
    return openMultiplier(
      playersBehind: playersBehind(game, p),
      tableSize: n,
      isSmallBlind: game.players.indexOf(p) == sbIndex,
      deadMoneyBb: bb <= 0 ? _noAnteDeadMoney : game.pot / bb,
      positionalProficiency: positionalProficiency,
    );
  }
}
