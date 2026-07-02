import 'dart:math';

import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/preflop_ranges.dart';
import 'package:monte/core/domain/ai/profile_policy.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/bot.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

/// Phase 1b: closed-loop calibration of a profile's preflop thresholds.
///
/// VPIP is a clean per-hand threshold, but PFR and 3-bet are
/// position-dependent — a PFR-range hand that faces a raise (and isn't a 3-bet)
/// flats instead of raising, so the open range must be *widened* to compensate.
/// The compensation depends on how often you face a raise (table dynamics), so
/// we measure it: simulate the profile against itself, compare measured vs target
/// frequencies, nudge the admitted fractions proportionally, and repeat to
/// convergence.
///
/// Pure engine (no UI / repository), so it stays Kotlin-portable.
class ProfileCalibrator {
  const ProfileCalibrator({
    this.playerCount = 6,
    this.iterations = 8,
    this.handsPerIteration = 5000,
    this.seed = 1,
  });

  final int playerCount;
  final int iterations;
  final int handsPerIteration;
  final int seed;

  static const _startingStack = 1000;

  /// Pre-seeded with the built-in pros' 6-max calibrations so seating them is
  /// instant (live calibration is ~1.5s). These are deterministic outputs of
  /// [calibrate]; if the strength model changes, re-run it and update these —
  /// `test/ai/profile_calibration_test.dart` guards that they still hit target.
  static final Map<String, PreflopRanges> _cache = {
    // Isaac Haxton (24 / 19.5 / 8) -> measured 23.8 / 19.6 / 8.4.
    '0.24_0.195_0.08_6': const PreflopRanges(
      vpip: 0.4871,
      pfr: 0.5086,
      threeBet: 0.5086,
    ),
    // Daniel Negreanu (26 / 21 / 9.5) -> measured 24.9 / 19.6 / 8.4.
    '0.26_0.21_0.095_6': const PreflopRanges(
      vpip: 0.4729,
      pfr: 0.5086,
      threeBet: 0.5086,
    ),
    // Michael Addamo (32 / 28 / 14) -> measured 32.8 / 23.8 / 10.2. PFR/3-bet
    // undershoot: 28/14 is a short-handed/HU target not soundly reachable at
    // 6-max (hitting it would require spewy light 3-bets).
    '0.32_0.28_0.14_6': const PreflopRanges(
      vpip: 0.4443,
      pfr: 0.4871,
      threeBet: 0.4871,
    ),
  };

  /// Calibrated ranges for [profile], cached by its targets + table size.
  PreflopRanges rangesFor(PlayerProfile profile) {
    final b = profile.strategicBaseline;
    final key =
        '${b.vpipTarget}_${b.pfrTarget}_${b.threeBetFrequency}_$playerCount';
    return _cache[key] ??= calibrate(profile);
  }

  /// Runs the calibration loop and returns the tuned ranges.
  PreflopRanges calibrate(PlayerProfile profile) {
    final b = profile.strategicBaseline;
    final targetVpip = b.vpipTarget;
    final target3 = b.threeBetFrequency;
    // PFR = opens + 3-bets, so the open frequency to aim for is PFR − 3-bet.
    final targetOpen = (b.pfrTarget - target3).clamp(0.0, 1.0);

    // Admitted fractions of all hands for each band, seeded from the targets.
    var qVpip = targetVpip;
    var qOpen = b.pfrTarget;
    var q3 = target3;

    var ranges = _rangesFrom(qVpip, qOpen, q3);
    for (var it = 0; it < iterations; it++) {
      final m = _measure(profile, ranges, seed + it);
      final measuredOpen = (m.pfr - m.threeBet).clamp(0.0, 1.0);

      qVpip = _step(qVpip, targetVpip, m.vpip);
      qOpen = _step(qOpen, targetOpen, measuredOpen);
      q3 = _step(q3, target3, m.threeBet);

      // Keep the bands nested: 3-bet ⊆ open ⊆ VPIP (tighter = smaller fraction).
      if (q3 > qOpen) q3 = qOpen;
      if (qOpen > qVpip) qVpip = qOpen;

      ranges = _rangesFrom(qVpip, qOpen, q3);
    }
    return ranges;
  }

  PreflopRanges _rangesFrom(double qVpip, double qOpen, double q3) =>
      PreflopRanges(
        vpip: PreflopRanges.thresholdForFraction(qVpip),
        pfr: PreflopRanges.thresholdForFraction(qOpen),
        threeBet: PreflopRanges.thresholdForFraction(q3),
      );

  /// One damped proportional step of the admitted fraction toward [target].
  double _step(double q, double target, double measured) {
    if (target <= 0) return 0.0;
    final ratio = measured <= 1e-6 ? 2.0 : (target / measured).clamp(0.5, 2.0);
    return (q * pow(ratio, 0.7)).clamp(0.002, 0.999);
  }

  /// Plays [handsPerIteration] hands with seat 0 running [profile] under
  /// [ranges] against a *reference field* of competent heuristic opponents (the
  /// realistic environment its stats reflect), and returns the hero's measured
  /// preflop frequencies (0–1 fractions). The button rotates, so the hero plays
  /// every position evenly.
  ({double vpip, double pfr, double threeBet}) _measure(
    PlayerProfile profile,
    PreflopRanges ranges,
    int runSeed,
  ) {
    final deckRandom = Random(runSeed);
    final hero = ProfilePolicy(
      profile,
      ranges: ranges,
      random: Random(runSeed * 7 + 1),
    );
    final field = <DecisionPolicy>[
      for (var i = 1; i < playerCount; i++)
        BotStrategy(random: Random(runSeed * 13 + i)),
    ];
    DecisionPolicy policyFor(int seat) => seat == 0 ? hero : field[seat - 1];

    final players = [
      for (var i = 0; i < playerCount; i++)
        Player(id: 'p$i', name: 'p$i', stack: _startingStack),
    ];
    final game = PokerGame(players: players, deck: Deck(random: deckRandom));

    var hands = 0, vpip = 0, pfr = 0, threeBet = 0;
    for (var h = 0; h < handsPerIteration; h++) {
      for (final p in players) {
        p.stack = _startingStack; // evaluation: top up so no one busts out
      }
      game.startHand();
      if (game.isHandOver) break;

      final heroDealt = players[0].hole.length == 2;
      var heroVpip = false, heroPfr = false, hero3bet = false;
      var priorRaise = false; // any preflop raise so far this hand

      while (!game.isHandOver) {
        final current = game.currentPlayer;
        if (current == null) break;
        final seat = players.indexOf(current);
        final preflop = game.board.isEmpty;
        final action = policyFor(seat).decide(game, current);
        if (preflop) {
          final isRaise = action.type == ActionType.bet ||
              action.type == ActionType.raise ||
              action.type == ActionType.allIn;
          if (seat == 0) {
            if (isRaise) {
              heroPfr = true;
              heroVpip = true;
              if (priorRaise) hero3bet = true;
            } else if (action.type == ActionType.call) {
              heroVpip = true;
            }
          }
          if (isRaise) priorRaise = true;
        }
        game.applyAction(action);
      }

      if (heroDealt) {
        hands++;
        if (heroVpip) vpip++;
        if (heroPfr) pfr++;
        if (hero3bet) threeBet++;
      }
    }

    if (hands == 0) return (vpip: 0, pfr: 0, threeBet: 0);
    return (
      vpip: vpip / hands,
      pfr: pfr / hands,
      threeBet: threeBet / hands,
    );
  }
}
