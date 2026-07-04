import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/features/eval_history/domain/profile_overrides.dart';

const _baseline = StrategicBaseline(
  vpipTarget: 0.40,
  pfrTarget: 0.07,
  threeBetFrequency: 0.01,
  gtoAdherenceWeight: 0.64,
);

void main() {
  group('ProfileOverrides', () {
    test('round-trips through JSON', () {
      final o = ProfileOverrides({frankDouglas.id: _baseline});
      final decoded = ProfileOverrides.fromJson(o.toJson());
      expect(decoded.length, 1);
      expect(decoded.byModel[frankDouglas.id]!.vpipTarget, 0.40);
      expect(decoded.byModel[frankDouglas.id]!.threeBetFrequency, 0.01);
    });

    test('apply swaps only the baseline, preserving identity/skill/modifiers', () {
      final o = ProfileOverrides({frankDouglas.id: _baseline});
      final tuned = o.apply(frankDouglas);

      expect(tuned.id, frankDouglas.id);
      expect(tuned.name, frankDouglas.name);
      expect(tuned.skill, frankDouglas.skill);
      expect(
        tuned.behavioralModifiers.exploitativeWeight,
        frankDouglas.behavioralModifiers.exploitativeWeight,
      );
      // ...but the preflop baseline is the tuned one.
      expect(tuned.strategicBaseline.vpipTarget, 0.40);
    });

    test('apply leaves an unlisted profile (e.g. a pro) unchanged', () {
      final o = ProfileOverrides({frankDouglas.id: _baseline});
      // A pro id isn't in the map → the exact same instance is returned.
      expect(identical(o.apply(isaacHaxton), isaacHaxton), isTrue);
    });

    test('empty overrides apply as identity', () {
      const o = ProfileOverrides.empty();
      expect(identical(o.apply(frankDouglas), frankDouglas), isTrue);
    });
  });
}
