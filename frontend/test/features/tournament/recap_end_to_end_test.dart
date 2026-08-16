import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/features/tournament/data/tournament_controller.dart';
import 'package:monte/features/tournament/domain/tournament_chronicle.dart';
import 'dart:math';

import 'package:monte/core/domain/ai/trigger_observer.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/domain/engine/deck.dart';
import 'package:monte/core/domain/engine/game.dart';
import 'package:monte/core/domain/engine/player.dart';
import 'package:monte/core/domain/hand_history.dart';
import 'package:monte/features/tournament/data/replay_builder.dart';
import 'package:monte/features/tournament/domain/chronicle/hand_narrator.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

/// Proves the whole commentary pipeline works on hands the *engine* actually
/// dealt, not on hand-built fixtures: real positions, real action, real board.
///
/// `HandNarrator` is unit-tested against constructed replays; this covers the
/// `ReplayBuilder` reconstruction in between, which is where the fiddly bits
/// (positions from the button, per-street pots, fold streets) live.
LevelRecap? _firstRecap({int seed = 11, int entrants = 27}) {
  final c = TournamentController.create(
    structure: TournamentStructure.wsopMainEvent(
      clockMode: LevelClockMode.hands,
    ),
    entrants: entrants,
    buyIn: 10000,
    tableSize: 9,
    seed: seed,
    // A human seat is what switches the chronicle on at all.
    humanSeat: true,
    names: ['You', for (var i = 1; i < entrants; i++) 'Bot $i'],
    botProfiles: [
      for (var i = 0; i < entrants - 1; i++)
        i.isEven
            ? builtInProfiles[i % builtInProfiles.length]
            : homeGameProfiles[i % homeGameProfiles.length],
    ],
  );
  try {
    // Play out level 1 so the level-end recap is generated.
    var guard = 0;
    while (c.lastRecap == null && guard++ < 20000) {
      if (c.state.status.name == 'finished') break;
      c.step();
    }
    return c.lastRecap;
  } finally {
    c.dispose();
  }
}

void main() {
  test('a real level produces a narrated feature hand', () {
    final recap = _firstRecap();
    expect(recap, isNotNull, reason: 'no recap was generated for level 1');

    final hand = recap!.featureHand;
    expect(hand, isNotNull, reason: 'the level had no replayable showdown');

    // --- the roster
    expect(hand!.seats.length, greaterThanOrEqualTo(2));
    expect(hand.bigBlind, greaterThan(0));
    for (final s in hand.seats) {
      expect(s.cards, hasLength(2), reason: '${s.name} had no hole cards');
      expect(s.startingStack, greaterThan(0));
      expect(s.stackBb(hand.bigBlind), greaterThan(0));
    }

    // Positions must be distinct — a duplicated button means the reconstruction
    // from buttonIndex is wrong.
    final positions = hand.seats.map((s) => s.position).toList();
    expect(
      positions.toSet().length,
      positions.length,
      reason: 'two seats share a position: $positions',
    );

    // --- the streets
    expect(hand.streets, isNotEmpty);
    for (final st in hand.streets) {
      expect(
        st.commentary,
        isNotEmpty,
        reason: '${st.name} got no commentary',
      );
      for (final line in st.commentary) {
        expect(line.trim(), isNotEmpty);
      }
    }
    // The board grows monotonically street by street.
    var seen = -1;
    for (final st in hand.streets) {
      expect(st.boardAfter.length, greaterThanOrEqualTo(seen));
      seen = st.boardAfter.length;
    }

    // --- the closing take and a verdict for every player in the roster
    expect(hand.commentary, isNotEmpty);
    expect(hand.verdicts, hasLength(hand.seats.length));
    for (final v in hand.verdicts) {
      expect(v.line.trim(), isNotEmpty);
    }
    expect(
      hand.verdicts.map((v) => v.name).toSet(),
      hand.seats.map((s) => s.name).toSet(),
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('commentary never leaks a placeholder or an empty substitution', () {
    final hand = _firstRecap()?.featureHand;
    expect(hand, isNotNull);
    final all = [
      for (final s in hand!.streets) ...s.commentary,
      ...hand.commentary,
      for (final v in hand.verdicts) v.line,
    ].join('\n');

    for (final bad in ['@', 'null', '  ', '0bb pot', 'nullbb']) {
      expect(all, isNot(contains(bad)), reason: 'leaked "$bad"');
    }
    // Grammar guards for the second-person path.
    for (final bad in ['You is', 'You has', 'You was', 'You keeps']) {
      expect(all, isNot(contains(bad)));
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('is deterministic for a seed', () {
    final a = _firstRecap(seed: 5)?.featureHand;
    final b = _firstRecap(seed: 5)?.featureHand;
    expect(a, isNotNull);
    expect(b, isNotNull);
    expect(a!.commentary, b!.commentary);
    expect(
      a.streets.map((s) => s.commentary).toList(),
      b.streets.map((s) => s.commentary).toList(),
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('a signature move survives the replay rebuild into recap text', () {
    // The integration risk is `ReplayBuilder`: it reconstructs a hand from the
    // engine's action log, and the fired moves have to come through it attached
    // to the right street and out the other side as words.
    //
    // Deliberately *not* "play a tournament and hope a move lands in the recap".
    // Only one hand per level is narrated, moves fire around eight times in a
    // level of 150 hands, and a rare event competing against the maximum over
    // 150 draws is a coin toss dressed up as a test. That the recap *prefers*
    // move-carrying hands is pinned deterministically in
    // `feature_hand_choice_test`; that the words are right is pinned in
    // `hand_narrator_test`. This is the seam between them.
    final players = [
      Player(id: 'p0', name: 'Ana', stack: 10000),
      Player(id: 'p1', name: 'Ben', stack: 10000),
    ];
    final game = PokerGame(
      players: players,
      smallBlind: 50,
      bigBlind: 100,
      deck: Deck(random: Random(9)),
    )..startHand();

    final actions = <ActionRecord>[];
    void act(GameAction a) {
      final p = game.currentPlayer!;
      actions.add(ActionRecord(
        playerId: p.id,
        street: game.round,
        type: a.type,
        amount: a.amount,
        potAfter: game.pot,
      ));
      game.applyAction(a);
    }

    var guard = 0;
    while (!game.isHandOver && guard++ < 60) {
      final p = game.currentPlayer;
      if (p == null) break;
      act(game.canCheck(p)
          ? const GameAction.check()
          : const GameAction.call());
    }

    final replay = ReplayBuilder.build(
      game: game,
      actions: actions,
      preChips: {'p0': 10000, 'p1': 10000},
      bigBlind: 100,
      firedTriggers: const [
        FiredTrigger('Slow_Play_Trap', 'p0', BettingRound.flop),
      ],
    );
    expect(replay, isNotNull, reason: 'both players saw the flop');

    // Attached to the street it happened on, and nowhere else.
    final flop =
        replay!.streets.firstWhere((s) => s.round == BettingRound.flop);
    expect(flop.triggers, hasLength(1));
    for (final s in replay.streets.where((s) => s.round != BettingRound.flop)) {
      expect(s.triggers, isEmpty, reason: '${s.name} picked up a stray move');
    }

    // And it comes out as words naming the move, on that street.
    final narrated = HandNarrator.narrate(replay);
    final text = narrated.streets
        .firstWhere((s) => s.round == BettingRound.flop)
        .commentary
        .join(' ')
        .toLowerCase();
    expect(text, contains('trap'));
    expect(text, contains('ana'));
  });
}
