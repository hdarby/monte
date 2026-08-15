import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';
import 'package:monte/features/table/data/local_game_repository.dart';

/// The calibration gate for postflop discipline.
///
/// A tuning-log review found pros continuing to 77% of turn bets and 71% of
/// river bets, and busting at 14.5 per 100 hands. Two causes: the perceived
/// villain range was ranked by *preflop* strength and never board-filtered, so a
/// bluff-catcher measured huge equity against a pile of unpaired big cards; and
/// the commitment gate was dormant below 100 BB — i.e. for all of tournament
/// play. This test pins the corrected frequencies so neither regresses.
///
/// The bands are deliberately two-sided. Over-folding is as wrong as
/// over-calling: it is exploitable, it plays like a robot, and an earlier
/// iteration of this fix sat at 83% fold-to-river-bet.
void main() {
  test('pros fold to postflop aggression at realistic frequencies', () async {
    final pros = builtInProfiles.take(8).toList();
    final hands = <EvalHand>[];
    final repo = LocalGameRepository(
      config: TableConfig(
        allBots: true,
        playerCount: pros.length,
        smallBlind: 1,
        bigBlind: 3,
        startingStack: 300,
        botThinkTime: Duration.zero,
        deckBuilder: () => Deck(random: Random(7)),
        seatBots: [for (final p in pros) BotSpec(profile: p)],
        onEvalHandRecorded: hands.add,
      ),
    );
    await repo.simulate(400);

    var bustouts = 0;
    final facing = <String, Map<String, int>>{};
    for (final h in hands) {
      final j = h.toJson();
      for (final p in (j['players'] as List)) {
        if ((p as Map)['finalStack'] == 0) bustouts++;
      }
      for (final street in const ['flop', 'turn', 'river']) {
        var bet = false;
        var potBefore = 0;
        var wager = 0;
        for (final a in (j['actions'] as List)) {
          final m = a as Map;
          if (m['street'] != street) continue;
          final t = m['type'] as String;
          if (bet && const ['fold', 'call', 'raise', 'allIn'].contains(t)) {
            final c = facing[street] ??= {};
            c[t] = (c[t] ?? 0) + 1;
            // Also bucket by how big the bet being faced was, as a share of the
            // pot before it went in.
            final frac = potBefore > 0 ? wager / potBefore : 0.0;
            final bucket = frac <= 0.4 ? 'small' : (frac >= 0.7 ? 'big' : 'mid');
            final b = facing[bucket] ??= {};
            b[t] = (b[t] ?? 0) + 1;
          }
          if (const ['bet', 'raise', 'allIn'].contains(t)) {
            if (!bet) {
              potBefore = (m['potAfter'] as int) - (m['amount'] as int);
              wager = m['amount'] as int;
            }
            bet = true;
          }
        }
      }
    }

    double foldRate(String street) {
      final c = facing[street] ?? {};
      final n = c.values.fold(0, (a, b) => a + b);
      expect(n, greaterThan(30), reason: 'too few $street decisions to judge');
      return (c['fold'] ?? 0) / n;
    }

    // Fold-to-bet is only meaningful *relative to the size being faced*: facing
    // a quarter-pot bet you need 17% equity and continuing wide is correct.
    // Since sizing became SPR-targeted, marginal hands bet small, so the raw
    // per-street rate legitimately fell. What has to hold is the shape — a big
    // bet folds out far more than a small one — and that a big bet is genuinely
    // respected. Before the fix, fold-to-bet was 37.7 / 22.6 / 28.9% by street
    // *regardless* of size, which is the pathology.
    expect(foldRate('big'), greaterThan(foldRate('small')) ,
        reason: 'a big bet must fold out more than a small one');
    expect(foldRate('big'), inInclusiveRange(0.45, 0.80),
        reason: 'a big bet should be respected, but not auto-folded to');
    expect(foldRate('small'), inInclusiveRange(0.15, 0.50),
        reason: 'a cheap bet should be called fairly wide — but not always');

    // Per street, continuing must still not be near-automatic the way it was.
    for (final street in const ['flop', 'turn', 'river']) {
      expect(foldRate(street), greaterThan(0.28),
          reason: '$street continues far too wide');
    }

    // Bustouts were 14.5 per 100 hands; the gate keeps them near a normal rate.
    final bustPer100 = 100 * bustouts / hands.length;
    expect(bustPer100, lessThan(9.0),
        reason: 'stack-offs should be coolers, not routine');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
