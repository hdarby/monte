// ignore_for_file: avoid_print
//
// Answers: how often does the search-backed evaluator agree with the
// heuristic on the same decision? Builds real postflop spots (varying
// street/opponent count/board texture, reusing bench_mcts.dart's approach),
// clones each one so both evaluators see an identical, unmutated game state,
// and compares the action *type* each one picks for the same profile.
// Run with: `dart run tool/compare_backends.dart`.
import 'dart:math';

import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/core/domain/ai/profile_postflop_policy.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

/// A 6-handed table, played passively (check/call) up to [streetBoardCount]
/// community cards, seeded so the same [seed] always produces the same spot.
PokerGame _spotAt(int seed, {required int streetBoardCount}) {
  final players = [
    for (var i = 0; i < 6; i++) Player(id: 'p$i', name: 'P$i', stack: 2000),
  ];
  final game = PokerGame(
    players: players,
    smallBlind: 5,
    bigBlind: 10,
    deck: Deck(random: Random(seed)),
    rotateButton: false,
  )..startHand();

  while (game.board.length < streetBoardCount && !game.isHandOver) {
    final p = game.currentPlayer;
    if (p == null) break;
    game.applyAction(
      game.canCheck(p) ? const GameAction.check() : const GameAction.call(),
    );
  }
  return game;
}

class _Tally {
  int total = 0;
  int agree = 0;
  final Map<String, int> heuristicActions = {};
  final Map<String, int> searchActions = {};
  final Map<String, int> pairCounts = {};

  void record(ActionType h, ActionType s) {
    total++;
    if (h == s) agree++;
    heuristicActions[h.name] = (heuristicActions[h.name] ?? 0) + 1;
    searchActions[s.name] = (searchActions[s.name] ?? 0) + 1;
    if (h != s) {
      final key = '${h.name}->${s.name}';
      pairCounts[key] = (pairCounts[key] ?? 0) + 1;
    }
  }

  double get agreeRate => total == 0 ? 0 : agree / total;
}

void main() {
  const streets = [3, 4, 5]; // flop, turn, river
  const spotsPerStreet = 60;
  final profiles = [danielNegreanu, ...builtInProfiles.skip(1).take(2)];

  for (final profile in profiles) {
    final tally = _Tally();
    for (final street in streets) {
      for (var seed = 0; seed < spotsPerStreet; seed++) {
        final game = _spotAt(2000 + seed, streetBoardCount: street);
        final hero = game.currentPlayer;
        if (hero == null) continue; // hand ended early at this seed; skip

        final heuristicGame = game.clone();
        final heuristicHero = heuristicGame.players
            .firstWhere((p) => p.id == hero.id);
        final heuristicPolicy = ProfilePostflopPolicy(
          profile,
          random: Random(42),
        );
        final heuristicAction =
            heuristicPolicy.decide(heuristicGame, heuristicHero);

        final searchGame = game.clone();
        final searchHero =
            searchGame.players.firstWhere((p) => p.id == hero.id);
        final searchPolicy = ProfilePostflopPolicy(
          profile,
          random: Random(42),
          tableCountProvider: () => 1,
        );
        final searchAction = searchPolicy.decide(searchGame, searchHero);

        tally.record(heuristicAction.type, searchAction.type);
      }
    }
    print('${profile.name}: agree ${(tally.agreeRate * 100).toStringAsFixed(1)}%'
        ' over ${tally.total} spots');
    print('  heuristic action mix: ${tally.heuristicActions}');
    print('  search action mix:    ${tally.searchActions}');
    if (tally.pairCounts.isNotEmpty) {
      print('  disagreements (heuristic->search): ${tally.pairCounts}');
    }
    print('');
  }
}
