import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';
import 'package:monte/core/domain/hand_history.dart';
import 'package:monte/features/tournament/data/replay_builder.dart';

import '../../_helpers.dart';

/// Drives a real [PokerGame] the same way `showdown_result_test.dart` does,
/// then feeds the resulting action log through [ReplayBuilder] to check
/// `equityWhenAllIn` is computed at the street the money actually went in on
/// — the bug `_suckout` had (it always used the flop board, regardless of
/// when stacks were actually committed).
void main() {
  group('ReplayBuilder.build equityWhenAllIn', () {
    test('a preflop all-in uses an empty board (AA vs KK, ~82/18)', () {
      // P0 has AA, P1 has KK; P0 shoves preflop, P1 calls all-in. Runout is
      // irrelevant to the equity number, only to who actually wins.
      final deck = Deck.stacked(
        cards('As Ks Ah Kh 2c 3d 4h 5s 6c 7d 8h 9s'),
      );
      final players = [
        Player(id: 'p0', name: 'P0', stack: 100),
        Player(id: 'p1', name: 'P1', stack: 100),
      ];
      final game = PokerGame(
        players: players,
        smallBlind: 1,
        bigBlind: 2,
        deck: deck,
        rotateButton: false,
      )..startHand();

      final pre = {for (final p in players) p.id: p.stack};
      final actions = <ActionRecord>[];
      while (!game.isHandOver) {
        final p = game.currentPlayer;
        if (p == null) break;
        final street = game.round;
        final action = const GameAction.allIn();
        game.applyAction(action);
        actions.add(
          ActionRecord(
            playerId: p.id,
            street: street,
            type: action.type,
            amount: action.amount,
            potAfter: game.pot,
          ),
        );
      }

      final replay = ReplayBuilder.build(
        game: game,
        actions: actions,
        preChips: pre,
        bigBlind: 2,
      );

      expect(replay, isNotNull);
      final eq = replay!.equityWhenAllIn;
      expect(eq, isNotNull);
      expect(eq!['p0'], closeTo(0.82, 0.05));
      expect(eq['p1'], closeTo(0.18, 0.05));
    });

    test('nobody all-in pre-showdown leaves equityWhenAllIn null', () {
      // Both players just check/call it down — nobody ever goes all-in.
      final deck = Deck.stacked(
        cards('2c 4h 3d 5s 6c As Kd Qh 8c Jc 9c Ts'),
      );
      final players = [
        Player(id: 'p0', name: 'P0', stack: 100),
        Player(id: 'p1', name: 'P1', stack: 100),
      ];
      final game = PokerGame(
        players: players,
        smallBlind: 1,
        bigBlind: 2,
        deck: deck,
        rotateButton: false,
      )..startHand();

      final pre = {for (final p in players) p.id: p.stack};
      final actions = <ActionRecord>[];
      while (!game.isHandOver) {
        final p = game.currentPlayer;
        if (p == null) break;
        final street = game.round;
        final action = game.canCheck(p)
            ? const GameAction.check()
            : const GameAction.call();
        game.applyAction(action);
        actions.add(
          ActionRecord(
            playerId: p.id,
            street: street,
            type: action.type,
            amount: action.amount,
            potAfter: game.pot,
          ),
        );
      }

      final replay = ReplayBuilder.build(
        game: game,
        actions: actions,
        preChips: pre,
        bigBlind: 2,
      );

      expect(replay, isNotNull);
      expect(replay!.equityWhenAllIn, isNull);
    });
  });
}
