import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';
import 'package:monte/core/domain/hand_history.dart';
import 'package:monte/features/tournament/data/chronicle_recorder.dart';
import 'package:monte/features/tournament/domain/tournament_chronicle.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart'
    show StandingKind;

/// A 6-max game (p0..p5), stack 20000, blinds 100/200, with [button] fixed —
/// p0 is always the human; varying [button] moves p0 through every seat.
PokerGame _sixMax(int button) {
  final players = [
    for (var i = 0; i < 6; i++)
      Player(id: 'p$i', name: 'P$i', stack: 20000, isHuman: i == 0),
  ];
  return PokerGame(
    players: players,
    smallBlind: 100,
    bigBlind: 200,
    deck: Deck(random: Random(1)),
    rotateButton: false,
  )
    ..buttonIndex = button
    ..startHand();
}

/// Drives the hand to completion via [choose] (called with the current
/// player each turn), recording an [ActionRecord] per action exactly the way
/// `TournamentController` does.
List<ActionRecord> _drive(PokerGame game, GameAction Function(Player cur) choose) {
  final actions = <ActionRecord>[];
  while (!game.isHandOver) {
    final cur = game.currentPlayer;
    if (cur == null) break;
    final street = game.round;
    final action = choose(cur);
    game.applyAction(action);
    actions.add(ActionRecord(
      playerId: cur.id,
      street: street,
      type: action.type,
      amount: action.amount,
      potAfter: game.pot,
    ));
  }
  return actions;
}

void main() {
  final kindsAndNames = () {
    final kinds = <String, StandingKind>{'p0': StandingKind.human};
    final names = <String, String>{'p0': 'You'};
    for (var i = 1; i < 6; i++) {
      kinds['p$i'] = StandingKind.pro;
      names['p$i'] = 'Bot $i';
    }
    return (kinds: kinds, names: names);
  }();

  ChronicleRecorder recorder(TournamentChronicle chronicle) => ChronicleRecorder(
        chronicle: chronicle,
        enabled: true,
        kindForSeat: (id) => kindsAndNames.kinds[id] ?? StandingKind.pro,
        profileForSeat: (id) => null,
      );

  /// Records [times] identical hands of the given shape and returns the
  /// resulting recap's `yourPlayStyle` lines (needs >= 5 hands dealt to emit
  /// anything at all — see `TournamentChronicle._yourPlayStyleLines`).
  ///
  /// [makeChoose] is called fresh for every hand — it must build a new
  /// closure (with its own mutable state) each time, or the "have I acted
  /// yet" flags from hand 1 leak into every later hand and the scenario stops
  /// being what the test claims it is by hand 2.
  List<String> playStyleAfter(
    int button,
    GameAction Function(Player cur) Function() makeChoose, {
    required int times,
  }) {
    final chronicle = TournamentChronicle();
    chronicle.beginLevel(
      {for (var i = 0; i < 6; i++) 'p$i': 20000},
      kindsAndNames.names,
      kindsAndNames.kinds,
      const {},
    );
    final rec = recorder(chronicle);
    for (var i = 0; i < times; i++) {
      final game = _sixMax(button);
      final actions = _drive(game, makeChoose());
      rec.recordHand(
        game,
        pre: {for (var i = 0; i < 6; i++) 'p$i': 20000},
        tableId: 1,
        busted: const {},
        levelIndex: 0,
        averageStack: 20000,
        humanTable: true,
        actions: actions,
      );
    }
    final recap = chronicle.buildRecap(
      levelJustFinished: 1,
      playersLeft: 6,
      averageStack: 20000,
      bigBlind: 200,
      paidPlaces: 0,
      inMoney: false,
      humanId: 'p0',
      currentChips: {for (var i = 0; i < 6; i++) 'p$i': 20000},
      finishPlaces: const {},
      prizes: const {},
    );
    return recap.yourPlayStyle;
  }

  test('a walk (blinds only) is dealt but never counts as VPIP', () {
    // button = 4 => p0 is the big blind (rank 1). Folding around gives p0 a
    // walk: no action ever recorded for them.
    final lines = playStyleAfter(4, () => (cur) => const GameAction.fold(), times: 5);
    expect(lines.join(' '), contains('0 of 5 hands'));
  });

  test('a button raise folded to is a steal attempt', () {
    // button = 0 => p0 is the button. Everyone folds to p0, who raises, then
    // the blinds fold too.
    GameAction Function(Player) makeChoose() {
      var raised = false;
      return (cur) {
        if (cur.id == 'p0' && !raised) {
          raised = true;
          return GameAction.raise(cur.stack); // an all-in raise is always legal
        }
        return const GameAction.fold();
      };
    }

    final lines = playStyleAfter(0, makeChoose, times: 5);
    expect(lines.join(' '), contains('5 of 5'));
    expect(lines.join(' '), contains('taken 5 of 5 late-position steal chances'));
  });

  test('raising over a live limper is not a steal chance', () {
    // button = 0 => p0 is the button. p3 (UTG) limps first, so the pot is not
    // folded to p0 even though nobody has raised.
    GameAction Function(Player) makeChoose() {
      final acted = <String>{};
      return (cur) {
        if (cur.id == 'p3' && !acted.contains('p3')) {
          acted.add('p3');
          return const GameAction.call(); // limp
        }
        if (cur.id == 'p0' && !acted.contains('p0')) {
          acted.add('p0');
          return GameAction.raise(cur.stack); // isolate the limper
        }
        return const GameAction.fold();
      };
    }

    final lines = playStyleAfter(0, makeChoose, times: 5).join(' ');
    expect(lines, contains('5 of 5')); // still VPIP — it's a real raise
    expect(lines, isNot(contains('steal chances')),
        reason: 'a limper already entered — this is an isolation raise, not '
            'a steal');
  });

  test('an early-position raise is never a steal chance, regardless of '
      'position math elsewhere', () {
    // button = 3 => p0 is UTG (first to act preflop, folded to by nobody —
    // there's nobody behind them to fold).
    GameAction Function(Player) makeChoose() {
      var raised = false;
      return (cur) {
        if (cur.id == 'p0' && !raised) {
          raised = true;
          return GameAction.raise(cur.stack);
        }
        return const GameAction.fold();
      };
    }

    final lines = playStyleAfter(3, makeChoose, times: 5).join(' ');
    expect(lines, contains('5 of 5')); // VPIP via RFI
    expect(lines, isNot(contains('steal chances')),
        reason: 'UTG has nobody behind to steal from');
  });
}
