@Timeout(Duration(minutes: 3))
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/amateur_policy.dart';
import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/core/domain/ai/profile_calibrator.dart';
import 'package:monte/core/domain/ai/profile_policy.dart';
import 'package:monte/core/domain/ai/profile_postflop_policy.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/features/analytics/domain/analytics.dart';
import 'package:monte/features/table/data/local_game_repository.dart';

/// The app's decider for a seated profile: the degraded [AmateurPolicy] for
/// amateurs (skill < 1), the calibrated pro brain otherwise. Seeded for repro.
DecisionPolicy _policyFor(PlayerProfile p, int seed) {
  final isAmateur =
      p.skill < 1.0 || homeGameProfiles.any((a) => a.id == p.id);
  if (isAmateur) return AmateurPolicy(p, random: Random(seed));
  return ProfilePolicy(
    p,
    ranges: const ProfileCalibrator().rangesFor(p),
    postflop: ProfilePostflopPolicy(p, random: Random(seed)),
    random: Random(seed),
  );
}

/// The pro field an amateur is measured against: the three built-in pros. An
/// amateur seated among only pros is the table's lone weak seat, so its win
/// rate is a clean read of "how badly does this player lose to pros" — no second
/// fish to feast on (which is what makes a mixed table's bb/100 misleading), and
/// unlike heads-up it doesn't expose the pros' 6-max ranges to blind-stealing.
final _proField = builtInProfiles;

/// Result of seating one [amateur] among [_proField]: the amateur's win rate and
/// the worst (minimum) pro win rate, both bb/100, averaged over seeds.
typedef _Standing = ({double amateur, double worstPro});

/// Seats [amateur] + the pro field (all-bots) and returns their win rates,
/// averaged over [seeds] with the lineup rotated each seed so no seat/position
/// is pinned. Stacks top up every hand, so bb/100 is a pure skill signal.
_Standing _seatAmongPros(
  PlayerProfile amateur, {
  required int hands,
  required List<int> seeds,
}) {
  final lineup = <PlayerProfile>[amateur, ..._proField];
  final sum = {for (final p in lineup) p.id: 0.0};
  for (final seed in seeds) {
    final seated = [
      for (var i = 0; i < lineup.length; i++)
        lineup[(i + seed) % lineup.length],
    ];
    final repo = LocalGameRepository(
      config: TableConfig(
        allBots: true,
        playerCount: seated.length,
        botThinkTime: Duration.zero,
        deckBuilder: () => Deck(random: Random(seed)),
        deciderBuilder: (i) => _policyFor(seated[i], seed * 100 + i),
      ),
    );
    repo.simulate(hands);
    for (final s in PokerAnalytics.compute(repo.history)) {
      final seat = int.parse(s.id.split('_')[1]);
      sum[seated[seat].id] = sum[seated[seat].id]! + s.bbPer100;
    }
    repo.dispose();
  }
  final avg = {for (final e in sum.entries) e.key: e.value / seeds.length};
  return (
    amateur: avg[amateur.id]!,
    worstPro: [for (final p in _proField) avg[p.id]!].reduce(min),
  );
}

void main() {
  group('amateur strength gate', () {
    const hands = 900;
    const seeds = [1, 2, 3];

    test('an amateur loses to a pro field; the best presses close', () {
      // Phil DiPinto is the owner's strongest amateur (8/10); Frank Douglas the
      // loose-passive station (3/10) — the two ends of the real roster.
      final strong = _seatAmongPros(philDiPinto, hands: hands, seeds: seeds);
      final station = _seatAmongPros(frankDouglas, hands: hands, seeds: seeds);

      // ignore: avoid_print
      print('among pros (bb/100): Phil DiPinto=${strong.amateur.toStringAsFixed(1)} '
          '(worst pro ${strong.worstPro.toStringAsFixed(1)}); '
          'Frank Douglas=${station.amateur.toStringAsFixed(1)} '
          '(worst pro ${station.worstPro.toStringAsFixed(1)})');

      // 1. Every amateur is a net loser to the pro field.
      expect(strong.amateur, lessThan(0),
          reason: 'the best amateur should still lose to a pro field');
      expect(station.amateur, lessThan(0),
          reason: 'the station should lose to a pro field');

      // 2. Every pro out-earns the amateur (pros never lose to an amateur).
      expect(strong.worstPro, greaterThan(strong.amateur),
          reason: 'a pro should out-earn the amateur');
      expect(station.worstPro, greaterThan(station.amateur));

      // 3. The best amateur presses close to break-even; the station is crushed.
      expect(strong.amateur, greaterThan(-_closeGapBb),
          reason: 'best amateur should press close to the pros');
      expect(strong.amateur, greaterThan(station.amateur + 40),
          reason: 'the best amateur should clearly beat the station');
    });

    test('higher skill loses less to a pro field (above the loss floor)', () {
      // Same style, only strength differs — isolates the skill dial. Each is
      // measured alone in the identical pro field, so the comparison is clean.
      //
      // Note the loss *floor*: against a pro field a stack-topped game caps how
      // much you can bleed per hand, so very-low skills (≲5/10) plateau near the
      // max loss and are indistinguishable within variance. Skill is monotonic
      // above that floor, so we sweep the responsive band (5/8/10) plus an extra
      // seed to clear sampling noise.
      PlayerProfile sweep(String id, int strength) => buildAmateur(
        id: id,
        name: id,
        strength: strength,
        vpip: 0.34,
        pfr: 0.16,
        threeBet: 0.03,
      );
      const sweepSeeds = [1, 2, 3, 4];
      final s5 = _seatAmongPros(sweep('S5', 5), hands: hands, seeds: sweepSeeds);
      final s8 = _seatAmongPros(sweep('S8', 8), hands: hands, seeds: sweepSeeds);
      final s10 =
          _seatAmongPros(sweep('S10', 10), hands: hands, seeds: sweepSeeds);

      // ignore: avoid_print
      print('skill sweep among pros: S5=${s5.amateur.toStringAsFixed(1)} '
          'S8=${s8.amateur.toStringAsFixed(1)} S10=${s10.amateur.toStringAsFixed(1)}');

      expect(s10.amateur, greaterThan(s8.amateur), reason: 'more skill => loses less');
      expect(s8.amateur, greaterThan(s5.amateur), reason: 'more skill => loses less');
      expect(s10.amateur, lessThan(0), reason: 'even the best amateur still loses');
    });
  });
}

/// How far the best amateur may trail break-even (bb/100) and still count as
/// "close but below" a pro. Observed: the strong-amateur example loses ~49 to a
/// pro field; this bound leaves headroom while still ruling out a crushing.
const double _closeGapBb = 90;
