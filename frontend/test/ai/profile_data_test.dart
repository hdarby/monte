import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';

/// Guards against the class of bug that corrupted Jeremy Ausmus: the player
/// creator's `_score` prompt asked for 0–100 but silently accepted `0.85` and
/// divided it by 100, writing a GTO adherence of 0.0085. The value stayed inside
/// its legal 0–1 range, so nothing complained — the bot just played as if it had
/// no strategy at all, and busted more than anyone else in the tuning log.
void main() {
  final all = <PlayerProfile>[...builtInProfiles, ...homeGameProfiles];

  group('shipped profile data', () {
    test('every profile has a unique id', () {
      final ids = all.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length,
          reason: 'duplicate ids collide in the roster and the reads book');
    });

    test('no scored value looks like a hundred-fold typo', () {
      for (final p in all) {
        // A genuine dial is either 0 (off) or a real fraction. Anything in
        // (0, 0.02) is a percentage that got divided by 100 twice.
        void check(String field, double v) {
          expect(v == 0 || v >= 0.02, isTrue,
              reason: '${p.name} (${p.id}) has $field = $v — '
                  'suspiciously small, likely entered as a fraction');
        }

        check('gtoAdherenceWeight', p.strategicBaseline.gtoAdherenceWeight);
        check('vpipTarget', p.strategicBaseline.vpipTarget);
        check('pfrTarget', p.strategicBaseline.pfrTarget);
        check('exploitativeWeight', p.behavioralModifiers.exploitativeWeight);
        for (final c in p.characteristics) {
          check('characteristic ${c.id}', c.proficiency);
        }
      }
    });

    test('a characteristic proficiency agrees with the dial it drives', () {
      // PlayerFactory.pro copies the GTO_Adherence proficiency into
      // gtoAdherenceWeight, so the two must never disagree.
      for (final p in all) {
        for (final c in p.characteristics.where((c) => c.id == 'GTO_Adherence')) {
          expect(c.proficiency,
              closeTo(p.strategicBaseline.gtoAdherenceWeight, 1e-9),
              reason: '${p.name} (${p.id}) has a GTO_Adherence proficiency '
                  'that disagrees with its adherence weight');
        }
      }
    });

    test('every profile passes its own validation', () {
      for (final p in all) {
        expect(p.validate(), isEmpty, reason: '${p.name} (${p.id})');
      }
    });
  });
}
