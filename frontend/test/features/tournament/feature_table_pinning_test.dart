import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/features/tournament/data/tournament_controller.dart';
import 'package:monte/features/tournament/domain/tournament_state.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

/// The feature table used to be recomputed on every publish — whichever
/// table had the most named (non-generated) personalities *right now* — so
/// a single bust-out anywhere in the field could flip it mid-level. It is
/// now a once-per-level broadcast choice: picked fresh at the start of each
/// level, then left alone even if it stops "qualifying" by the picking rule,
/// with the one exception of the table actually breaking entirely (in which
/// case the level finishes with no feature table, rather than swapping to a
/// substitute nobody was watching).
void main() {
  TournamentController buildController() {
    final named = builtInProfiles.take(5).toList();
    final filler = builtInProfiles[5].renamed('Filler', generated: true);

    // Table A (id 0): 2 named + 2 generated bots.
    // Table B (id 1): 3 named + 1 generated bot — starts with more named
    // players, so B is the initial pick over A. All-bot (no human seat):
    // feature-table nomination is a field-wide property that doesn't need
    // one, and it sidesteps the chronicle recorder entirely (only active
    // with a human seated, and not exercised by this test).
    final c = TournamentController.create(
      structure: TournamentStructure.turbo(clockMode: LevelClockMode.hands),
      entrants: 8,
      buyIn: 100,
      tableSize: 4,
      seed: 1,
      botProfiles: [
        named[0], named[1], filler, filler,
        named[2], named[3], named[4], filler,
      ],
    );
    // Override seatDraw's random table assignment with the exact split
    // these tests need.
    c.state.tables = [
      TournamentTable(id: 0, playerIds: ['e0', 'e1', 'e2', 'e3']),
      TournamentTable(id: 1, playerIds: ['e4', 'e5', 'e6', 'e7']),
    ];
    return c;
  }

  int handsPerLevelOf(TournamentController c) =>
      c.state.structure.levelAt(0).durationHands!;

  test('stays on the pinned table for the rest of the level, even once it '
      'would no longer qualify from scratch', () {
    final c = buildController();
    final handsPerLevel = handsPerLevelOf(c);

    // Headless play never picks a feature table until the first level
    // advance (the live-play entrypoint, `startLive`, picks up front
    // instead) — so cross into level 2 first.
    for (var i = 0; i <= handsPerLevel; i++) {
      c.step();
    }
    expect(c.featureTableId, 1, reason: 'B starts with more named players');

    // Bust all three of B's named players — a plain re-pick from scratch
    // would now favor A (2 named vs B's 0) — but B is still a real,
    // standing table, so the level-long pin must hold regardless. Only a
    // *few* more hands, deliberately: a full level's worth would cross the
    // next level boundary and trigger a legitimate fresh re-pick, which is
    // not what this is testing.
    c.state.recordBustouts(['e4']);
    c.state.recordBustouts(['e5']);
    c.state.recordBustouts(['e6']);
    c.step();
    c.step();
    expect(c.featureTableId, 1,
        reason: 'B is still standing — the pin holds for the whole level');
  });

  test('drops to no feature table if the pinned table actually breaks, '
      'rather than substituting another one', () {
    final c = buildController();
    final handsPerLevel = handsPerLevelOf(c);

    for (var i = 0; i <= handsPerLevel; i++) {
      c.step();
    }
    expect(c.featureTableId, 1);

    // Empty table B completely — the pinned table itself protects it from
    // being the one a rebalance *breaks* when another table is available to
    // break instead, so the only way it actually ceases to exist is if
    // every one of its own players busts out.
    c.state.recordBustouts(['e4']);
    c.state.recordBustouts(['e5']);
    c.state.recordBustouts(['e6']);
    c.state.recordBustouts(['e7']);
    c.step();

    expect(c.featureTableId, null,
        reason: 'the pinned table broke — finish the level without one');

    // Stays null for the rest of the level; no substitute is chosen even
    // though table A (with its 2 named players) still qualifies.
    c.step();
    c.step();
    expect(c.featureTableId, null);
  });
}
