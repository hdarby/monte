@Timeout(Duration(minutes: 4))
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/amateur_policy.dart';
import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/hand_evaluator.dart';
import 'package:monte/features/table/data/local_game_repository.dart';

void main() {
  // Guards that amateurs stay believable: no calling off the river with air, and
  // no epidemic of light 100bb stack-offs. Seeded, so the numbers are stable.
  test('amateurs play a believable game (no river air-calls, bounded stack-offs)',
      () {
    // A deliberately spicy home-game table: LAGs, stations, and TAGs.
    final table = [mitch, justinVidovitch, frankDouglas, patWray, philDiPinto, dougNiemec];

    final repo = LocalGameRepository(
      config: TableConfig(
        allBots: true,
        playerCount: table.length,
        smallBlind: 1,
        bigBlind: 3,
        startingStack: 300,
        botThinkTime: Duration.zero,
        deckBuilder: () => Deck(random: Random(7)),
        deciderBuilder: (i) => AmateurPolicy(table[i], random: Random(100 + i)),
      ),
    );
    repo.simulate(600);

    const stack = 300;
    var hands = 0, stackOffHands = 0, weakStackOffs = 0;
    var bigBets = 0, weakBigBets = 0; // postflop bet/raise >= 3/4 pot
    var riverCalls = 0, riverAirCalls = 0, riverBigAirCalls = 0;

    for (final h in repo.history) {
      hands++;
      final bb = h.bigBlind;
      final board = h.board.map(Card.fromCode).toList();
      final byId = {for (final p in h.players) p.id: p};

      // A stack-off = a player who committed their whole buy-in (busted this
      // hand). The policy expresses shoves as bet/raise-to-stack, so detect via
      // final stacks rather than the all-in action type.
      final busted = h.finalStacks.entries.where((e) => e.value == 0).toList();
      if (busted.isNotEmpty) {
        stackOffHands++;
        for (final e in busted) {
          final p = byId[e.key];
          if (p != null && p.revealed && p.holeCards.length == 2 && board.length >= 3) {
            final hv = HandEvaluator.evaluate(
                [...p.holeCards.map(Card.fromCode), ...board]);
            if (hv.rank.index <= HandRank.pair.index) weakStackOffs++;
          }
        }
      }

      // Postflop aggression: big bets/raises, and how often the aggressor showed
      // down a weak hand (aggression not supported by holdings).
      var potBefore = h.bigBlind * 3;
      for (final a in h.actions) {
        final isBet = a.type == ActionType.bet || a.type == ActionType.raise;
        if (a.street != BettingRound.preflop && isBet) {
          if (a.amount >= 0.75 * potBefore || a.amount >= 0.6 * stack) {
            bigBets++;
            final p = byId[a.playerId];
            if (p != null && p.revealed && p.holeCards.length == 2 && board.length >= 3) {
              final hv = HandEvaluator.evaluate(
                  [...p.holeCards.map(Card.fromCode), ...board]);
              if (hv.rank.index <= HandRank.pair.index) weakBigBets++;
            }
          }
        }
        potBefore = a.potAfter;

        if (a.street == BettingRound.river && a.type == ActionType.call) {
          riverCalls++;
          final p = byId[a.playerId];
          if (p != null && p.revealed && p.holeCards.length == 2) {
            final hv = HandEvaluator.evaluate(
                [...p.holeCards.map(Card.fromCode), ...board]);
            if (hv.rank == HandRank.highCard) {
              riverAirCalls++;
              if (a.amount >= 5 * bb) riverBigAirCalls++;
            }
          }
        }
      }
    }

    // ignore: avoid_print
    print('=== amateur realism probe over $hands hands ===');
    // ignore: avoid_print
    print('stack-off hands: $stackOffHands '
        '(${(stackOffHands / hands * 100).toStringAsFixed(1)}%); '
        'weak (<=pair) stack-offs shown: $weakStackOffs');
    // ignore: avoid_print
    print('big postflop bets/raises: $bigBets; '
        'of shown, weak (<=pair): $weakBigBets '
        '(${bigBets == 0 ? 0 : (weakBigBets / bigBets * 100).toStringAsFixed(1)}%)');
    // ignore: avoid_print
    print('river calls: $riverCalls; '
        'air calls (high card at showdown): $riverAirCalls '
        '(${riverCalls == 0 ? 0 : (riverAirCalls / riverCalls * 100).toStringAsFixed(1)}%); '
        'BIG air calls (>=5bb): $riverBigAirCalls');

    // No calling off a real river bet with a hand that can't beat a pair — the
    // core unrealistic behavior the owner flagged. Structurally guaranteed by
    // AmateurPolicy's river made-hand floor.
    expect(riverBigAirCalls, 0,
        reason: 'no amateur should call off a big river bet with air');
    expect(riverAirCalls, lessThanOrEqualTo((riverCalls * 0.02).ceil()),
        reason: 'river air-calls should be negligible');

    // Aggression stays believable: even this spicy table shouldn't stack off
    // 100bb in a large share of hands, nor mostly with weak holdings.
    expect(stackOffHands, lessThan((hands * 0.15).round()),
        reason: 'too many full-stack all-ins for 100bb play');
    expect(weakStackOffs, lessThan((hands * 0.06).round()),
        reason: 'too many all-ins unsupported by holdings');
  });
}
