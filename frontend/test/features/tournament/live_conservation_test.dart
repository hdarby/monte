import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/features/tournament/data/tournament_controller.dart';
import 'package:monte/features/tournament/domain/tournament_state.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

/// Drives the *live* path (human table played hand-by-hand, other tables
/// simulated between hands) and asserts the total chips never drift from
/// entrants x starting stack — simulating action off the human's table must
/// never create or destroy chips.
Future<void> _run({
  required int entrants,
  required int seed,
  TournamentStructure? structure,
  int maxHumanHands = 1 << 30,
}) async {
  final s = structure ?? TournamentStructure.turbo(clockMode: LevelClockMode.hands);
  final c = TournamentController.create(
    structure: s,
    entrants: entrants,
    buyIn: 100,
    tableSize: 9,
    seed: seed,
    humanSeat: true,
    names: [for (var i = 0; i < entrants; i++) i == 0 ? 'You' : 'Bot $i'],
  );
  final total = entrants * s.startingStack;
  void check(String where) {
    final sum = c.state.players.values.fold(0, (a, p) => a + p.chips);
    expect(sum, total, reason: 'seed $seed $where: chips drifted');
  }

  check('start');
  await c.startLive(botDelay: Duration.zero);

  // Cap the human's hands so a deep structure (which never busts a folding human
  // for hundreds of hands) still terminates the test — the point is that off-
  // table simulation runs and conserves, not that the whole field resolves.
  var humanHands = 0;
  var guard = 0;
  while (c.state.status != TournamentStatus.finished &&
      humanHands < maxHumanHands &&
      guard++ < 2000000) {
    check('during');
    if (!c.awaitingHuman) {
      await Future<void>.delayed(Duration.zero);
      continue;
    }
    final g = c.liveGame!;
    final me = g.currentPlayer!;
    // Fold to any bet, otherwise check — keeps the human passive so plenty of
    // off-table simulation happens before they bust.
    final action = g.canCheck(me)
        ? const GameAction(ActionType.check)
        : const GameAction(ActionType.fold);
    humanHands++;
    await c.submitLiveAction(action);
  }
  check('end');
  c.dispose();
}

void main() {
  test('live small field conserves chips through off-table simulation', () async {
    for (final seed in [1, 2, 5]) {
      await _run(entrants: 27, seed: seed);
    }
  });

  test('live large field conserves chips', () async {
    for (final seed in [1, 3]) {
      await _run(entrants: 120, seed: seed);
    }
  });

  test('live deep 900-runner field simulates all tables without hanging', () async {
    // ~100 tables, 600 BB deep. A folding human survives far longer than the
    // test should run, so cap the hands — this asserts the per-round off-table
    // simulation stays conserved and fast at scale (no attrition shortcut).
    await _run(
      entrants: 900,
      seed: 1,
      structure: TournamentStructure.wsopMainEvent(clockMode: LevelClockMode.hands),
      maxHumanHands: 40,
    );
  });

  test('human busting a large field finalizes promptly with a full finish order',
      () async {
    const entrants = 500;
    final s = TournamentStructure.wsopCircuit(clockMode: LevelClockMode.hands);
    final c = TournamentController.create(
      structure: s,
      entrants: entrants,
      buyIn: 100,
      tableSize: 9,
      seed: 2,
      humanSeat: true,
      names: [for (var i = 0; i < entrants; i++) i == 0 ? 'You' : 'Bot $i'],
    );
    addTearDown(c.dispose);
    await c.startLive(botDelay: Duration.zero);

    // The human jams every hand, so they bust deep in the field fast. When they
    // do, the tournament must finalize promptly (settle by chips) — not grind
    // thousands of unwatched hands — with everyone assigned a place.
    var guard = 0;
    while (c.state.status != TournamentStatus.finished && guard++ < 100000) {
      if (!c.awaitingHuman) {
        await Future<void>.delayed(Duration.zero);
        continue;
      }
      await c.submitLiveAction(const GameAction(ActionType.allIn));
    }

    expect(c.state.status, TournamentStatus.finished);
    expect(c.state.players['e0']!.finishPlace, isNotNull);
    expect(c.state.finishOrder.length, entrants); // everyone placed
    expect(
        c.state.players.values.where((p) => p.finishPlace == 1).length, 1);
  });
}
