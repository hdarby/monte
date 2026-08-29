// ignore_for_file: avoid_print
//
// Standalone benchmark, not a `flutter test` file — deliberately. CLAUDE.md's
// own testing philosophy avoids hardware-coupled, flaky ms-based assertions;
// "fast enough" for the MCTS cutover (see the mcts-cutover plan) is a UX
// judgment call the owner makes from real numbers on their own machine, not a
// portable CI invariant. Run with: `dart run tool/bench_mcts.dart`.
import 'dart:math';

import 'package:monte/core/domain/ai/ismcts.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

/// A 6-handed table, played passively (check/call) up to [street] streets of
/// community cards, seeded so every trial at a given [seed] sees the same
/// spot regardless of iteration count — an apples-to-apples comparison.
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

class _Spot {
  const _Spot(this.label, this.streetBoardCount);
  final String label;
  final int streetBoardCount;
}

void main() {
  const spots = [
    _Spot('flop, 6-handed limped pot', 3),
    _Spot('turn, 6-handed limped pot', 4),
    _Spot('river, 6-handed limped pot', 5),
  ];
  const iterationCounts = [100, 250, 500, 1000, 1500];
  const trialsPerCell = 5;

  print(
    'IsmctsEngine.chooseAction cost — $trialsPerCell trials per cell, '
    'ms per decision\n',
  );
  print(
    'spot'.padRight(28) +
        [for (final n in iterationCounts) '$n'.padLeft(8)].join(),
  );

  for (final spot in spots) {
    final avgMs = <double>[];
    for (final iterations in iterationCounts) {
      final times = <int>[];
      for (var t = 0; t < trialsPerCell; t++) {
        // Same seed per trial index across iteration counts, so every column
        // in a row is measuring literally the same board/hand/opponents.
        final game = _spotAt(1000 + t, streetBoardCount: spot.streetBoardCount);
        final hero = game.currentPlayer;
        if (hero == null) continue; // hand ended early at this seed; skip
        final engine = IsmctsEngine(
          config: IsmctsConfig(iterations: iterations),
          random: Random(42),
        );
        final sw = Stopwatch()..start();
        engine.chooseAction(game, hero);
        sw.stop();
        times.add(sw.elapsedMilliseconds);
      }
      final avg = times.isEmpty
          ? double.nan
          : times.reduce((a, b) => a + b) / times.length;
      avgMs.add(avg);
    }
    print(
      spot.label.padRight(28) +
          [for (final ms in avgMs) ms.toStringAsFixed(1).padLeft(8)].join(),
    );
  }

  print(
    '\nProjection: at N opponents seeing a flop and ~3 decisions/street '
    'reached, added wall-clock per hand ≈ (ms/decision) × 3 × N. Compare '
    'against a UX bar for how long a live hand may pause before the next '
    'deal.',
  );
}
