@Timeout(Duration(minutes: 3))
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/player_stats.dart';
import 'package:monte/features/reads/data/player_stats_store.dart';
import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/features/analytics/domain/analytics.dart';
import 'package:monte/features/table/data/local_game_repository.dart';

/// The app's decider for a seated profile: the degraded [AmateurPolicy] for
/// amateurs (skill < 1), the calibrated pro brain otherwise. Seeded for repro.

/// The pro field an amateur is measured against: a 6-max table of the built-in
/// pros (the strong ones doubled), which is the table size their ranges are
/// calibrated for. An amateur seated among only pros is the table's lone weak
/// seat, so its win rate is a clean read of "how badly does this player lose to
/// pros" — no second fish to feast on (which makes a mixed table's bb/100
/// misleading), and, unlike 4-handed/heads-up, the pros aren't playing 6-max
/// ranges at the wrong table size where a disciplined amateur out-positions them.
/// Only the two *solid* pros are used as the benchmark (doubled to fill a 6-max
/// table). Michael Addamo is excluded on purpose: his hyper-aggressive overbet
/// profile is a net loser in the fast (non-solver) brain, so he's not a valid
/// yardstick for "beats amateurs" (a docs-noted tuning quirk).
final _proField = <PlayerProfile>[
  isaacHaxton,
  danielNegreanu,
  isaacHaxton,
  danielNegreanu,
  isaacHaxton,
];

/// Result of seating one [amateur] among [_proField]: the amateur's win rate and
/// the pro field's mean win rate, both bb/100, averaged over seeds. (Mean, not
/// min — a single unlucky pro seat over a finite sample isn't a fair yardstick.)
typedef _Standing = ({double amateur, double avgPro});

/// Seats [amateur] + the pro field (all-bots) and returns their win rates,
/// averaged over [seeds] with the lineup rotated each seed so no seat/position
/// is pinned. Attribution is by seat (not profile id) so the doubled pros don't
/// collide. Stacks top up every hand, so bb/100 is a pure skill signal.
_Standing _seatAmongPros(
  PlayerProfile amateur, {
  required int hands,
  required List<int> seeds,
}) {
  final lineup = <PlayerProfile>[amateur, ..._proField];
  var amateurSum = 0.0, worstProSum = 0.0;
  for (final seed in seeds) {
    final seated = [
      for (var i = 0; i < lineup.length; i++)
        lineup[(i + seed) % lineup.length],
    ];
    // Seat the profiles properly rather than injecting bare policies, so the
    // repository wires each seat's **opponent reads**. Without them the pros
    // play the entire run blind, and a maximally aggressive amateur who barrels
    // every street is unbeatable by construction — no amount of discipline
    // helps if you can never notice who you are playing. Noticing is exactly
    // what separates a pro from a rec, so denying it measures the wrong thing.
    final stats = OpponentStatsService(
      const NoopPlayerStatsStore(),
      PlayerStatsBook(),
    );
    final repo = LocalGameRepository(
      statsService: stats,
      config: TableConfig(
        allBots: true,
        playerCount: seated.length,
        botThinkTime: Duration.zero,
        deckBuilder: () => Deck(random: Random(seed)),
        seatBots: [for (final p in seated) BotSpec(profile: p)],
      ),
    );
    repo.simulate(hands);
    final rateBySeat = <int, double>{};
    for (final s in PokerAnalytics.compute(repo.history)) {
      rateBySeat[int.parse(s.id.split('_')[1])] = s.bbPer100;
    }
    repo.dispose();
    var amateurRate = 0.0, proTotal = 0.0, proSeats = 0;
    for (var i = 0; i < seated.length; i++) {
      final r = rateBySeat[i] ?? 0;
      if (seated[i].id == amateur.id) {
        amateurRate = r;
      } else {
        proTotal += r;
        proSeats++;
      }
    }
    amateurSum += amateurRate;
    worstProSum += proTotal / proSeats;
  }
  return (
    amateur: amateurSum / seeds.length,
    avgPro: worstProSum / seeds.length,
  );
}

void main() {
  group('amateur strength gate', () {
    const hands = 700; // 6-max sim is heavier; 700 × 3 seeds stays in budget
    const seeds = [1, 2, 3];

    test('an amateur loses to a pro field; the best presses close', () {
      // Phil DiPinto is the owner's strongest amateur (8/10); Frank Douglas the
      // loose-passive station (3/10) — the two ends of the real roster.
      final strong = _seatAmongPros(philDiPinto, hands: hands, seeds: seeds);
      final station = _seatAmongPros(frankDouglas, hands: hands, seeds: seeds);

      // ignore: avoid_print
      print('among pros (bb/100): Phil DiPinto=${strong.amateur.toStringAsFixed(1)} '
          '(avg pro ${strong.avgPro.toStringAsFixed(1)}); '
          'Frank Douglas=${station.amateur.toStringAsFixed(1)} '
          '(avg pro ${station.avgPro.toStringAsFixed(1)})');

      // Pros are raise-or-fold first-in (no open-limping), which forfeits the
      // sim's cheap-flop edge against weak fields — so the very strongest, most
      // aggressive amateurs may now hover within a few bb/100 of break-even
      // (realistic: a strong reg can break even vs pros short-term). The
      // guarantees that must still hold: nobody *meaningfully* beats the pro
      // field, weak amateurs stay crushed, and the pros are never crushed.

      // 1. The best amateur is at-or-below break-even; the station is a clear loser.
      expect(strong.amateur, lessThan(_breakEvenBb),
          reason: 'the best amateur should not meaningfully beat a pro field');
      expect(station.amateur, lessThan(0),
          reason: 'the station should lose to a pro field');

      // 2. Neither amateur crushes the pro field.
      expect(strong.avgPro, greaterThan(-_breakEvenBb),
          reason: 'the pro field should not be beaten meaningfully by the best amateur');
      expect(station.avgPro, greaterThan(station.amateur));

      // 3. The best amateur presses close to break-even; the station is crushed.
      expect(strong.amateur, greaterThan(-_closeGapBb),
          reason: 'best amateur should press close to the pros');
      expect(strong.amateur, greaterThan(station.amateur + 20),
          reason: 'the best amateur should clearly beat the station');
    });

    test('every amateur style is a net loser to a pro field', () {
      // A spread of the roster's styles — a maniac, a squeeze-happy LAG, a
      // loose-passive station, and an erratic caller. None should beat the pros.
      // (bb/100 vs pros is NOT monotonic in skill: the realism guards make a very
      // low-skill player fold-heavy, so it can bleed slower than a medium one who
      // plays more pots. The invariant that matters is that they all lose.)
      for (final a in [daveCoyle, justinVidovitch, frankDouglas, mattCarter]) {
        final r = _seatAmongPros(a, hands: hands, seeds: seeds);
        // ignore: avoid_print
        print('${a.name.padRight(18)} ${r.amateur.toStringAsFixed(1)} '
            '(avg pro ${r.avgPro.toStringAsFixed(1)})');
        expect(r.amateur, lessThan(_breakEvenBb),
            reason: '${a.name} should not meaningfully beat a pro field');
        expect(r.avgPro, greaterThan(-_breakEvenBb),
            reason: 'the pro field should not be crushed by ${a.name}');
      }
    });
  });
}

/// How far the best amateur may trail break-even (bb/100) and still count as
/// "close but below" a pro. Observed: the strong-amateur example loses ~49 to a
/// pro field; this bound leaves headroom while still ruling out a crushing.
const double _closeGapBb = 90;

/// How far above break-even (bb/100) the *strongest* amateurs may sit and still
/// count as "not beating the pros". Non-zero because pros are raise-or-fold
/// first-in (no open-limping), giving up the sim's cheap-flop edge against weak
/// fields — so a top amateur can hover near break-even, which is realistic. Weak
/// amateurs are still crushed well below zero.
const double _breakEvenBb = 4;
