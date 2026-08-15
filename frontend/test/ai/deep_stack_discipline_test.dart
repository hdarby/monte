import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';
import 'package:monte/features/table/data/local_game_repository.dart';

/// Level 1 of the WSOP Main Event: 60,000 stacks at 100/200, i.e. **300 BB
/// deep** — the deepest spot in the game, and where the field should be playing
/// small pots and close to the vest.
///
/// It was producing ~1.5 bust-outs per 100 hands, which across ~1,100 tables is
/// hundreds of players gone in the first level. Three separate places measured
/// stack depth from the player's *remaining* stack, so the depth read collapsed
/// as chips went in and the deep-stack discipline switched itself off exactly
/// when the pot was bloating — worst preflop, where a 4-bet war left the bot
/// believing it was short and shipping 300 BB with QQ. A fourth gate only fired
/// when a single call crossed 40% of stack, so a pot built over three streets
/// walked straight past it.
void main() {
  test('a 300 BB field plays small pots and rarely busts', () async {
    const bb = 200;
    // A realistic Main Event mix: half pros, half recreational.
    final field = [
      for (var i = 0; i < 9; i++)
        i.isEven
            ? builtInProfiles[i % builtInProfiles.length]
            : homeGameProfiles[i % homeGameProfiles.length],
    ];
    final hands = <EvalHand>[];
    final repo = LocalGameRepository(
      config: TableConfig(
        allBots: true,
        playerCount: field.length,
        smallBlind: 100,
        bigBlind: bb,
        startingStack: 60000,
        botThinkTime: Duration.zero,
        deckBuilder: () => Deck(random: Random(7)),
        seatBots: [for (final p in field) BotSpec(profile: p)],
        onEvalHandRecorded: hands.add,
      ),
    );
    await repo.simulate(1200);

    var bustouts = 0;
    final pots = <double>[];
    for (final h in hands) {
      final j = h.toJson();
      for (final p in (j['players'] as List).cast<Map>()) {
        if (p['finalStack'] == 0) bustouts++;
      }
      final acts = (j['actions'] as List).cast<Map>();
      pots.add(acts.isEmpty ? 0 : (acts.last['potAfter'] as int) / bb);
    }
    pots.sort();
    double q(double f) =>
        pots[(pots.length * f).clamp(0, pots.length - 1).toInt()];

    // Busting 300 BB deep should take a cooler, not a routine hand. Was 1.5.
    expect(100 * bustouts / hands.length, lessThan(0.6),
        reason: 'too many players busting in level 1');

    // Pots must stay small relative to the stacks: a pot fraction compounds, so
    // without depth control a 15 BB preflop pot reaches 160 BB by the river.
    expect(q(0.5), lessThan(25), reason: 'median pot bloated');
    expect(q(0.9), lessThan(160), reason: '90th-percentile pot bloated');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
