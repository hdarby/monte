import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/features/eval_history/domain/eval_hand.dart';
import 'package:monte/features/tournament/data/tournament_controller.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

/// Tournament hands are the ones the player actually cares about, and until this
/// was wired they were the only hands producing no record — the eval store was
/// fed solely by the single cash table, so no post-session review of a
/// tournament was possible at all.
void main() {
  test('the human table writes a full-information hand to the store', () async {
    final recorded = <EvalHand>[];
    final c = TournamentController.create(
      structure: TournamentStructure.wsopMainEvent(),
      entrants: 9,
      buyIn: 10000,
      seed: 7,
      tableSize: 9,
      humanSeat: true,
      botProfiles: builtInProfiles.take(8).toList(),
      onEvalHandRecorded: recorded.add,
    );
    c.startLive();

    for (var i = 0; i < 300 && recorded.isEmpty; i++) {
      if (c.awaitingHuman) {
        await c.submitLiveAction(const GameAction.fold());
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    }
    c.dispose();

    expect(recorded, isNotEmpty,
        reason: 'no tournament hand ever reached the store');
    final h = recorded.first;
    expect(h.sessionId, isNotNull, reason: 'sessions must be separable');
    expect(h.timestampMs, isNotNull);
    expect(h.playersRemaining, isNotNull,
        reason: 'a shove near a pay jump is only judgeable against the field');
    expect(h.players, isNotEmpty);
    for (final p in h.players) {
      expect(p.holeCards.length, 2, reason: '${p.name} has no cards recorded');
    }
  });
}
