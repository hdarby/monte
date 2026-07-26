// A watchable, headless single-table sit-and-go driven by the REAL poker engine
// + real bots + the M1 tournament domain. It doubles as an integration test:
// real hands are dealt, blinds rise, players bust with finish places + prizes,
// and one champion is crowned — proving the domain drives real play end to end.
//
// Rising blinds, big-blind antes (M2), elimination, and payouts are all real.
//
// ignore_for_file: avoid_print
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/engine/decision_policy.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';
import 'package:monte/features/tournament/domain/payout_structure.dart';
import 'package:monte/features/tournament/domain/tournament_state.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

void main() {
  test('single-table SNG plays to a champion with correct payouts', () {
    const seats = 6;
    const buyIn = 100;
    final structure = TournamentStructure.turbo(
      clockMode: LevelClockMode.hands,
      startingStack: 1500,
    );

    // Field + live tournament state (one table).
    final names = ['You', 'Ivan', 'Mai', 'Rex', 'Lena', 'Ото'];
    final players = <String, TournamentPlayer>{
      for (var i = 0; i < seats; i++)
        'p$i': TournamentPlayer(
          id: 'p$i', name: names[i], isHuman: i == 0, chips: structure.startingStack),
    };
    final state = TournamentState(
      structure: structure,
      payouts: PayoutStructure.forFieldSize(seats),
      buyIn: buyIn,
      players: players,
      tables: [TournamentTable(id: 0, playerIds: players.keys.toList())],
    );

    // Engine seats + one heuristic decider per seat (fast + deterministic).
    final seatPlayers = [
      for (final p in players.values)
        Player(id: p.id, name: p.name, stack: p.chips, isHuman: p.isHuman),
    ];
    final deciders = <String, DecisionPolicy>{
      for (var i = 0; i < seatPlayers.length; i++)
        seatPlayers[i].id: buildDecider(BotType.heuristic, random: Random(100 + i)),
    };

    print('=== ${structure.name} SNG — $seats players, \$$buyIn buy-in, '
        'pool \$${state.prizePool}, top ${state.paidPlaces} paid ===');
    print('payouts: ${state.payoutTable}\n');

    PokerGame buildGame(int levelIndex, int button) {
      final lvl = structure.levelAt(levelIndex);
      return PokerGame(
        players: seatPlayers,
        smallBlind: lvl.smallBlind,
        bigBlind: lvl.bigBlind,
        ante: lvl.ante, // M2: big-blind antes now live
        deck: Deck(random: Random(7 * (levelIndex + 1))),
      )..buttonIndex = button;
    }

    var builtLevel = -1;
    late PokerGame game;
    var button = 0;
    var handNo = 0;

    while (state.status != TournamentStatus.finished && handNo < 2000) {
      if (state.levelIndex != builtLevel) {
        builtLevel = state.levelIndex;
        game = buildGame(builtLevel, button);
        final l = state.currentLevel;
        print('-- Level ${l.level}: blinds ${l.smallBlind}/${l.bigBlind} '
            '(${state.playersRemaining} left, avg ${state.averageStack}) --');
      }

      // Chips at the start of the hand — used to order same-hand bustouts.
      final preChips = {for (final p in seatPlayers) p.id: p.stack};

      game.startHand();
      if (game.isHandOver) break; // not enough funded players
      handNo++;
      while (!game.isHandOver) {
        final cur = game.currentPlayer;
        if (cur == null) break;
        game.applyAction(deciders[cur.id]!.decide(game, cur));
      }
      button = game.buttonIndex;

      // Sync chips back and record any bustouts (worst-first by pre-hand chips).
      for (final sp in seatPlayers) {
        state.players[sp.id]!.chips = sp.stack;
      }
      final busted = [
        for (final p in state.players.values)
          if (p.isActive && p.chips == 0) p.id,
      ]..sort((a, b) => preChips[a]!.compareTo(preChips[b]!));
      if (busted.isNotEmpty) {
        state.recordBustouts(busted);
        for (final id in busted) {
          final p = state.players[id]!;
          final prize = p.prizeWon > 0 ? ' — \$${p.prizeWon}' : '';
          print('   ✗ ${p.name} busts, ${_ordinal(p.finishPlace!)} place$prize');
        }
      }

      if (state.playersRemaining <= 1) {
        state.declareChampion();
        break;
      }
      state.handsThisLevel++;
      state.maybeAdvanceLevel();
    }

    // Final standings, best first.
    final standings = state.players.values.toList()
      ..sort((a, b) => (a.finishPlace ?? 0).compareTo(b.finishPlace ?? 0));
    print('\n=== Final standings (after $handNo hands) ===');
    for (final p in standings) {
      final prize = p.prizeWon > 0 ? '  \$${p.prizeWon}' : '';
      print('  ${_ordinal(p.finishPlace!)}  ${p.name}$prize');
    }

    // Correctness gates.
    expect(state.status, TournamentStatus.finished);
    expect(state.finishOrder.length, seats);
    final champ = state.players.values.firstWhere((p) => p.finishPlace == 1);
    expect(champ.chips, greaterThan(0));
    final paidOut = state.players.values.fold(0, (a, p) => a + p.prizeWon);
    expect(paidOut, state.prizePool); // every chip of the pool is awarded
  });
}

String _ordinal(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  return switch (n % 10) { 1 => '${n}st', 2 => '${n}nd', 3 => '${n}rd', _ => '${n}th' };
}
