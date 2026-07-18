import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/characteristic_catalog.dart';
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
}
