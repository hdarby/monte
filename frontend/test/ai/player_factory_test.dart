import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/characteristic_catalog.dart';
import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/player_factory.dart';
import 'package:monte/core/domain/ai/player_profile.dart';

void main() {
  group('PlayerFactory.recreational', () {
    test('maps strength to a sub-pro skill and keeps a valid profile', () {
      final p = PlayerFactory.recreational(
        id: 'H099',
        name: 'Test Fish',
        strength: 3,
        vpip: 0.45,
        pfr: 0.10,
        opponentReading: 0.4,
        generalTraits: const GeneralTraits(potOdds: 0.2),
        description: 'calls too much',
      );
      expect(p.skill, lessThan(1.0));
      expect(p.skill, greaterThan(0.0));
      expect(p.strategicBaseline.vpipTarget, 0.45);
      // Opponent-reading score lands on the behavioral field.
      expect(p.behavioralModifiers.weightOnOpponentHistory, 0.4);
      expect(p.generalTraits.potOdds, 0.2);
      expect(p.description, 'calls too much');
      expect(p.validate(), isEmpty);
    });
  });

  group('PlayerFactory.pro', () {
    test('a GTO_Adherence characteristic drives gtoAdherenceWeight', () {
      final p = PlayerFactory.pro(
        id: 'P099',
        name: 'Test Pro',
        vpip: 0.24,
        pfr: 0.20,
        threeBet: 0.09,
        gtoAdherence: 0.5, // should be overridden by the characteristic
        characteristics: const [
          PlayerCharacteristic(id: 'GTO_Adherence', proficiency: 0.92),
          PlayerCharacteristic(id: 'Soul_Read', proficiency: 0.7),
        ],
        description: 'balanced with reads',
      );
      expect(p.strategicBaseline.gtoAdherenceWeight, 0.92);
      expect(p.characteristics, hasLength(2));
      expect(p.skill, 1.0);
      expect(p.validate(), isEmpty);
    });

    test('falls back to the gtoAdherence arg without the characteristic', () {
      final p = PlayerFactory.pro(
        id: 'P098',
        name: 'No GTO char',
        vpip: 0.3,
        pfr: 0.25,
        threeBet: 0.12,
        gtoAdherence: 0.83,
      );
      expect(p.strategicBaseline.gtoAdherenceWeight, 0.83);
    });
  });

  group('PlayerFactory.nextId', () {
    test('picks the next free zero-padded slot', () {
      expect(PlayerFactory.nextId('P', {'P001', 'P002'}), 'P003');
      expect(PlayerFactory.nextId('H', {'H001', 'H003'}), 'H002');
      expect(PlayerFactory.nextId('P', const <String>{}), 'P001');
    });
  });

  group('characteristicCatalog', () {
    test('is non-empty with unique ids and a lookup', () {
      expect(characteristicCatalog, isNotEmpty);
      final ids = characteristicCatalog.map((c) => c.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      expect(characteristicById('GTO_Adherence')?.drivesGtoAdherence, isTrue);
      expect(characteristicById('nope'), isNull);
    });
  });

  group('recreational players can carry characteristics', () {
    // AmateurPolicy reads the three tilt styles straight off the profile, but
    // there was no way to put one there: buildAmateur took no characteristics,
    // PlayerFactory.recreational took none, no shipped rec had any, and the
    // creator only asked pros. So every recreational accumulated tilt pressure
    // and expressed none of it — the tilt layer was dead code for the exact
    // population it was built for.
    test('the factory forwards them', () {
      final p = PlayerFactory.recreational(
        id: 'H900',
        name: 'Chaser',
        strength: 4,
        characteristics: const [
          PlayerCharacteristic(id: 'Tilt_Chase', proficiency: 0.7),
        ],
      );
      expect(p.proficiencyOf('Tilt_Chase'), 0.7);
    });

    test('buildAmateur forwards them', () {
      final p = buildAmateur(
        id: 'H901',
        name: 'Blower',
        strength: 3,
        characteristics: const [
          PlayerCharacteristic(id: 'Tilt_Blowup', proficiency: 0.9),
        ],
      );
      expect(p.proficiencyOf('Tilt_Blowup'), 0.9);
    });

    test('defaults to none, so existing profiles are unchanged', () {
      final p = PlayerFactory.recreational(
        id: 'H902',
        name: 'Plain',
        strength: 5,
      );
      expect(p.characteristics, isEmpty);
      expect(p.proficiencyOf('Tilt_Chase'), 0.0);
    });

    test('every move the amateur brain reads is in the catalog and reachable',
        () {
      // The guard against re-introducing the same hole: a proficiency the
      // amateur policy consults must be nameable by the creator (catalogued)
      // and attachable to a recreational (forwarded by the factory).
      const readByAmateurPolicy = [
        'Tilt_Blowup',
        'Tilt_Chase',
        'Tilt_Shutdown',
      ];
      final known = characteristicCatalog.map((c) => c.id).toSet();
      for (final id in readByAmateurPolicy) {
        expect(known, contains(id), reason: '$id is read but not catalogued');
        final p = PlayerFactory.recreational(
          id: 'H903',
          name: 'Carrier',
          strength: 5,
          characteristics: [
            PlayerCharacteristic(id: id, proficiency: 0.5),
          ],
        );
        expect(p.proficiencyOf(id), 0.5,
            reason: '$id cannot be attached to a recreational');
      }
    });
  });
}
