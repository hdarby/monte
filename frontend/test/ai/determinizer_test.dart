import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/determinizer.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/card.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';

List<Player> _fourHanded() => [
  Player(id: 'p0', name: 'P0', stack: 1000, isHuman: true),
  Player(id: 'p1', name: 'P1', stack: 1000),
  Player(id: 'p2', name: 'P2', stack: 1000),
  Player(id: 'p3', name: 'P3', stack: 1000),
];

/// Sets up a 4-handed hand where UTG (p3) folds, leaving p0 (button) to act
/// with one folded opponent — the search's decision point.
PokerGame _withOneFolder() {
  final game = PokerGame(
    players: _fourHanded(),
    deck: Deck(random: Random(7)),
  )..startHand();
  game.applyAction(const GameAction.fold()); // p3 (UTG) folds
  return game;
}

void main() {
  group('Determinizer', () {
    test('hero keeps real cards; in-hand opponents get fresh ones, folders '
        'get none', () {
      final game = _withOneFolder();
      final hero = game.currentPlayer!; // p0
      expect(hero.id, 'p0');
      final heroHole = [...hero.hole];

      final det = Determinizer(random: Random(1)).determinize(game, hero);

      final heroDet = det.players.firstWhere((p) => p.id == 'p0');
      expect(heroDet.hole, heroHole, reason: 'hero cards are unchanged');

      // In-hand opponents are re-dealt two cards; the folder has none.
      for (final p in det.players.where((p) => p.id != 'p0')) {
        expect(p.hole, hasLength(p.inHand ? 2 : 0));
      }
      expect(det.players.firstWhere((p) => p.id == 'p3').hole, isEmpty);
    });

    test('no card is duplicated across hands and board', () {
      final game = _withOneFolder();
      final hero = game.currentPlayer!;

      final det = Determinizer(random: Random(2)).determinize(game, hero);

      final all = <Card>[...det.board, for (final p in det.players) ...p.hole];
      expect(all.toSet(), hasLength(all.length), reason: 'all cards distinct');
    });

    test('opponent cards never collide with what the hero can see', () {
      final game = _withOneFolder();
      final hero = game.currentPlayer!;
      final known = {...hero.hole, ...game.board};

      final det = Determinizer(random: Random(3)).determinize(game, hero);

      for (final p in det.players.where((p) => p.id != 'p0')) {
        expect(p.hole.any(known.contains), isFalse);
      }
    });

    test('is reproducible under a fixed seed', () {
      final game = _withOneFolder();
      final hero = game.currentPlayer!;

      List<List<Card>> holes(PokerGame g) => [
        for (final p in g.players) [...p.hole],
      ];

      final a = Determinizer(random: Random(42)).determinize(game, hero);
      final b = Determinizer(random: Random(42)).determinize(game, hero);
      expect(holes(a), holes(b));
    });

    test('a determinized world plays to showdown and conserves chips', () {
      final game = _withOneFolder();
      final hero = game.currentPlayer!;
      final det = Determinizer(random: Random(5)).determinize(game, hero);
      final chipsBefore =
          det.pot + det.players.fold<int>(0, (s, p) => s + p.stack);

      var guard = 0;
      while (det.currentPlayer != null) {
        final p = det.currentPlayer!;
        det.applyAction(
          det.canCheck(p) ? const GameAction.check() : const GameAction.call(),
        );
        if (++guard > 1000) fail('did not terminate');
      }

      expect(det.isHandOver, isTrue);
      final chipsAfter = det.players.fold<int>(0, (s, p) => s + p.stack);
      expect(chipsAfter, chipsBefore);
    });
  });
}
