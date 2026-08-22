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

    test('every pro profile is calibrator-feasible', () {
      // famous_pros.dart promises this in its header comment and nothing was
      // checking it. An infeasible set of targets does not fail loudly — the
      // calibrator just cannot reach them, so the profile quietly plays a
      // frequency nobody chose.
      //
      // Pros only. Recreationals go through AmateurPolicy's `_leakyRanges`,
      // never ProfileCalibrator, so this envelope does not apply to them — and
      // should not: a 50/8 calling station or a 75-VPIP maniac is the whole
      // point of those profiles, not a mistake to be tuned away.
      for (final p in builtInProfiles) {
        final b = p.strategicBaseline;
        expect(
          PlayerProfile.preflopFeasibility(
            vpip: b.vpipTarget,
            pfr: b.pfrTarget,
            threeBet: b.threeBetFrequency,
          ),
          isEmpty,
          reason: '${p.name} (${p.id})',
        );
      }
    });

    test('nobody carries more than one tilt style', () {
      // Blow-up, chase and shutdown are mutually exclusive *shapes*, not dials
      // that stack: a player who widens-and-raises, widens-and-calls, and
      // tightens all at once just cancels into mush. Four authored pros held all
      // three at the same time before this existed.
      const styles = ['Tilt_Blowup', 'Tilt_Chase', 'Tilt_Shutdown'];
      for (final p in all) {
        final held = p.characteristics
            .where((c) => styles.contains(c.id) && c.proficiency > 0)
            .map((c) => c.id)
            .toList();
        expect(held.length, lessThanOrEqualTo(1),
            reason: '${p.name} (${p.id}) holds $held');
      }
    });

    test('no two profiles share a name', () {
      // Ids are checked above, but a duplicated *name* is what a human notices
      // at the table, and the roster has near-collisions already (Jamie Dwan
      // and Tom Dwan; Luc and Sam Greenwood; Michael and Robert Mizrachi).
      final names = all.map((p) => p.name).toList();
      final dupes = <String>{
        for (final n in names)
          if (names.where((x) => x == n).length > 1) n,
      };
      expect(dupes, isEmpty, reason: 'duplicate names: $dupes');
    });
  });
}
