import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/amateur_policy.dart';
import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/core/domain/ai/profile_decider.dart';
import 'package:monte/core/domain/ai/profile_policy.dart';
import 'package:monte/features/tournament/data/tournament_controller.dart';
import 'package:monte/features/tournament/domain/tournament_state.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

void main() {
  test('deciderForProfile routes pros and amateurs to the right brains', () {
    expect(deciderForProfile(isaacHaxton), isA<ProfilePolicy>());
    expect(deciderForProfile(homeGameProfiles.first), isA<AmateurPolicy>());
  });

  test('renamed changes only the name, keeping id/skill/style', () {
    final r = isaacHaxton.renamed('Alias Smith');
    expect(r.name, 'Alias Smith');
    expect(r.id, isaacHaxton.id);
    expect(r.skill, isaacHaxton.skill);
    // Same brain: a renamed pro still plays like a pro.
    expect(deciderForProfile(r).runtimeType,
        deciderForProfile(isaacHaxton).runtimeType);
  });

  test('a tournament seats the chosen personalities and plays them out', () {
    final field = [
      isaacHaxton,
      danielNegreanu,
      homeGameProfiles.first,
      homeGameProfiles.first,
      homeGameProfiles.first,
    ];
    final c = TournamentController.create(
      structure: TournamentStructure.turbo(
          clockMode: LevelClockMode.hands, startingStack: 400),
      entrants: field.length + 1,
      buyIn: 100,
      tableSize: 6,
      seed: 3,
      humanSeat: true,
      names: ['You', ...field.map((p) => p.name)],
      botProfiles: field,
    );

    // Seats carry the chosen personalities' names (e0 is the human).
    expect(c.state.players['e0']!.name, 'You');
    expect(c.state.players['e1']!.name, isaacHaxton.name);
    expect(c.state.players['e2']!.name, danielNegreanu.name);

    // The field plays down to a champion with the whole pool paid out.
    c.runToCompletion();
    expect(c.state.status, TournamentStatus.finished);
    expect(c.state.players.values.where((p) => p.finishPlace == 1).length, 1);
    expect(
        c.state.players.values.fold(0, (a, p) => a + p.prizeWon), c.state.prizePool);
  });
}
