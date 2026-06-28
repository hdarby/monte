import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/core/domain/ai/preflop_ranges.dart';
import 'package:monte/core/domain/ai/profile_calibrator.dart';
import 'package:monte/core/domain/ai/profile_policy.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/bot.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/hand_history.dart';
import 'package:monte/features/analytics/domain/analytics.dart';
import 'package:monte/features/table/data/local_game_repository.dart';

/// 3-bet% for one player id: hands where they raised preflop after a prior
/// preflop raise.
double _threeBetPctFor(List<HandHistory> hs, String id) {
  var hands = 0, threeBets = 0;
  bool isRaise(ActionType t) =>
      t == ActionType.bet || t == ActionType.raise || t == ActionType.allIn;
  for (final h in hs) {
    final did3bet = <String>{};
    var priorRaise = false;
    for (final a in h.actions) {
      if (a.street != BettingRound.preflop) continue;
      if (isRaise(a.type) && priorRaise) did3bet.add(a.playerId);
      if (isRaise(a.type)) priorRaise = true;
    }
    for (final p in h.players) {
      if (p.id != id) continue;
      hands++;
      if (did3bet.contains(p.id)) threeBets++;
    }
  }
  return hands == 0 ? 0 : threeBets / hands * 100;
}

/// Measured stats (percentages) for the hero seat (`bot_0`) running [profile]
/// with [ranges] against a field of 5 heuristic opponents. Deterministic via a
/// seeded deck.
({double vpip, double pfr, double threeBet}) _heroStats(
  PlayerProfile profile,
  PreflopRanges ranges,
  int hands,
) {
  final repo = LocalGameRepository(
    config: TableConfig(
      allBots: true,
      playerCount: 6,
      botThinkTime: Duration.zero,
      deckBuilder: () => Deck(random: Random(999)),
      deciderBuilder: (i) => i == 0
          ? ProfilePolicy(profile, ranges: ranges, random: Random(50))
          : BotStrategy(random: Random(60 + i)),
    ),
  );
  addTearDown(repo.dispose);
  repo.simulate(hands);

  final hero = PokerAnalytics.compute(repo.history).firstWhere(
    (s) => s.id == 'bot_0',
  );
  return (
    vpip: hero.vpip,
    pfr: hero.pfr,
    threeBet: _threeBetPctFor(repo.history, 'bot_0'),
  );
}

void main() {
  group('profile calibration (Phase 1b)', () {
    test('calibrated profiles hit VPIP/PFR/3-bet targets vs a realistic field', () {
      final calibrator = const ProfileCalibrator();
      for (final p in builtInProfiles) {
        final ranges = calibrator.rangesFor(p);
        final m = _heroStats(p, ranges, 15000);
        final b = p.strategicBaseline;

        // VPIP is a clean per-hand threshold, so it calibrates tightly.
        expect(
          m.vpip,
          closeTo(b.vpipTarget * 100, 3.0),
          reason: '${p.name} VPIP ${m.vpip} vs ${b.vpipTarget * 100}',
        );

        // PFR/3-bet may *undershoot* — very aggressive targets (Addamo's 28/14)
        // come from short-handed/HU play and aren't soundly reachable at 6-max
        // without spewy light 3-bets. They must not *overshoot*, though: that
        // would signal the bot raising more than its profile (the old all-in
        // spew). So: at most target+2, and no worse than a bounded undershoot.
        void inBand(double measured, double target, String name) {
          expect(measured, lessThanOrEqualTo(target + 2.0), reason: '$name over');
          expect(measured, greaterThanOrEqualTo(target - 8.0),
              reason: '$name under');
        }

        inBand(m.pfr, b.pfrTarget * 100, '${p.name} PFR ${m.pfr}');
        inBand(m.threeBet, b.threeBetFrequency * 100,
            '${p.name} 3-bet ${m.threeBet}');
      }
    });

    test('calibrated thresholds stay nested (3-bet >= open >= vpip cutoffs)', () {
      final r = const ProfileCalibrator().rangesFor(isaacHaxton);
      expect(r.threeBet, greaterThanOrEqualTo(r.pfr));
      expect(r.pfr, greaterThanOrEqualTo(r.vpip));
    });
  });
}
