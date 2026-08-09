import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/features/tournament/data/tournament_controller.dart';
import 'package:monte/features/tournament/domain/tournament_chronicle.dart';
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
}
