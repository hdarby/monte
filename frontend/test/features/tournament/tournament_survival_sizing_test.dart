import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/icm_adjusted_decider.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/core/domain/ai/profile_decider.dart';
import 'package:monte/core/domain/ai/tournament_context.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';
import 'package:monte/features/table/data/local_game_repository.dart';

/// The direct test of the tournament-realism complaint: the same 300 BB, level-1
/// field (see `deep_stack_discipline_test.dart`) should bust fewer players and
/// size its preflop raises measurably smaller in a tournament than the
/// identical lineup would in cash — see `IcmAdjustedDecider._survivalPressure`.
///
/// `TournamentController` itself is not used here — it plays a whole event to a
/// champion, which is both too slow for a unit test and moves past level 1
/// immediately. Instead this wraps each seat's decider in `IcmAdjustedDecider`
/// with a synthetic level-1 `TournamentContext` (huge field, nowhere near the
/// money — `bubbleFactor`/`ladderPressure` both genuinely 0 there, exactly as
/// `TournamentController.contextOf` would compute), via `TableConfig`'s
/// `deciderBuilder` seam, and runs it through the same engine loop as the cash
/// baseline. That isolates the mechanism under test from the rest of the
/// tournament feature.
void main() {
  const bb = 200;
  const startingStack = 60000; // 300 BB
  final field = [
    for (var i = 0; i < 9; i++)
      i.isEven
          ? builtInProfiles[i % builtInProfiles.length]
          : homeGameProfiles[i % homeGameProfiles.length],
  ];

  Future<List<EvalHand>> simulate({required bool tournament}) async {
    final hands = <EvalHand>[];
    final repo = LocalGameRepository(
      config: TableConfig(
        allBots: true,
        playerCount: field.length,
        smallBlind: bb ~/ 2,
        bigBlind: bb,
        startingStack: startingStack,
        botThinkTime: Duration.zero,
        deckBuilder: () => Deck(random: Random(7)),
        seatBots: [for (final p in field) BotSpec(profile: p)],
        onEvalHandRecorded: hands.add,
        deciderBuilder: tournament
            ? (seatIndex) {
                final profile = field[seatIndex];
                final base = deciderForProfile(profile,
                    random: Random(seatIndex + 1));
                // Level 1 of a huge field, nowhere near the money: bubbleFactor
                // and ladderPressure are genuinely 1.0/0 here, same as the real
                // controller would compute — only the new baseline pressure in
                // `_survivalPressure` is active.
                const ctx = TournamentContext(
                  stackInBb: 300,
                  bubbleFactor: 1.0,
                  playersLeft: 1100,
                  paidPlaces: 110,
                  inMoney: false,
                );
                return IcmAdjustedDecider(
                  base,
                  (g, p) => ctx,
                  profile: profile,
                  icmDiscipline: !isAmateurProfile(profile),
                  random: Random(seatIndex + 100),
                );
              }
            : null,
      ),
    );
    await repo.simulate(800);
    return hands;
  }

  /// The preflop open size and 3-bet size, in BB, for every hand that had one —
  /// the first and second preflop raise/bet actions overall, in order.
  ({List<double> opens, List<double> threeBets}) preflopSizes(
      List<EvalHand> hands) {
    final opens = <double>[], threeBets = <double>[];
    for (final h in hands) {
      final j = h.toJson();
      final acts = (j['actions'] as List).cast<Map>();
      var raiseCount = 0;
      for (final a in acts) {
        if (a['street'] != 'preflop') continue;
        final type = a['type'] as String;
        if (type != 'raise' && type != 'bet') continue;
        raiseCount++;
        final sizeBb = (a['amount'] as int) / bb;
        if (raiseCount == 1) opens.add(sizeBb);
        if (raiseCount == 2) threeBets.add(sizeBb);
      }
    }
    return (opens: opens, threeBets: threeBets);
  }

  int bustouts(List<EvalHand> hands) {
    var n = 0;
    for (final h in hands) {
      final j = h.toJson();
      for (final p in (j['players'] as List).cast<Map>()) {
        if (p['finalStack'] == 0) n++;
      }
    }
    return n;
  }

  double mean(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;

  test('a level-1 tournament busts no more players than the cash equivalent',
      () async {
    final cash = await simulate(tournament: false);
    final tourney = await simulate(tournament: true);
    final cashBustRate = 100 * bustouts(cash) / cash.length;
    final tourneyBustRate = 100 * bustouts(tourney) / tourney.length;
    expect(tourneyBustRate, lessThanOrEqualTo(cashBustRate + 0.1),
        reason: 'survival pressure must not make level 1 busier than cash');
    expect(tourneyBustRate, lessThan(0.6),
        reason: 'the original complaint: level 1 should rarely bust anyone');
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('preflop opens and 3-bets are measurably smaller in the tournament',
      () async {
    final cash = await simulate(tournament: false);
    final tourney = await simulate(tournament: true);
    final cashSizes = preflopSizes(cash);
    final tourneySizes = preflopSizes(tourney);

    expect(cashSizes.opens, isNotEmpty);
    expect(tourneySizes.opens, isNotEmpty);
    expect(mean(tourneySizes.opens), lessThan(mean(cashSizes.opens)),
        reason: 'the same field must open smaller under survival pressure — '
            'this is the literal "cash and tournaments feel the same" fix');

    expect(cashSizes.threeBets, isNotEmpty);
    expect(tourneySizes.threeBets, isNotEmpty);
    expect(mean(tourneySizes.threeBets), lessThan(mean(cashSizes.threeBets)));
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('amateur VPIP drops in the tournament but is not collapsed to a nit',
      () async {
    final cashHands = await simulate(tournament: false);
    final tourneyHands = await simulate(tournament: true);
    // `LocalGameRepository` names bot seats 'bot_$i' in `field` order — using
    // that directly, rather than `players[].modelId`, because `deciderBuilder`
    // (used for every seat in the tournament sim) makes `_deciderForBot` record
    // a profile-less `BotSpec`, which leaves `modelId` unable to identify the
    // profile at all in that sim.
    final amateurSeatIds = {
      for (var i = 0; i < field.length; i++)
        if (isAmateurProfile(field[i])) 'bot_$i',
    };

    double amateurVpip(List<EvalHand> hands) {
      var dealt = 0, vpip = 0;
      for (final h in hands) {
        final j = h.toJson();
        final acts = (j['actions'] as List).cast<Map>();
        for (final id in amateurSeatIds) {
          dealt++;
          final voluntary = acts.any((a) =>
              a['street'] == 'preflop' &&
              a['playerId'] == id &&
              (a['type'] == 'call' ||
                  a['type'] == 'raise' ||
                  a['type'] == 'bet' ||
                  a['type'] == 'allIn'));
          if (voluntary) vpip++;
        }
      }
      return dealt == 0 ? 0 : vpip / dealt;
    }

    final cashVpip = amateurVpip(cashHands);
    final tourneyVpip = amateurVpip(tourneyHands);
    expect(tourneyVpip, lessThan(cashVpip),
        reason: 'the garbage-call trim should tighten amateurs somewhat');
    expect(tourneyVpip, greaterThan(cashVpip * 0.7),
        reason: 'but not collapse them into a nit — personality is a plus');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
