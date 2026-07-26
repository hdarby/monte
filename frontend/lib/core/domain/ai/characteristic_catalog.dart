import 'package:meta/meta.dart';

/// The catalog of **special characteristics** a player can be given — the
/// "growing set" of bespoke traits/mechanics. Each is selected with a 0–1
/// proficiency (see [PlayerCharacteristic]).
///
/// Some characteristics map onto an existing scalar dial (e.g. [gtoAdherence]'s
/// proficiency drives `StrategicBaseline.gtoAdherenceWeight`); others name a
/// bespoke `EngineTriggers` mechanic that is captured as data now and wired into
/// play later. New entries are added here as the owner authors them.
@immutable
class CharacteristicSpec {
  const CharacteristicSpec({
    required this.id,
    required this.name,
    required this.description,
    this.drivesGtoAdherence = false,
  });

  /// Stable identifier stored on a profile's `PlayerCharacteristic.id` (and, for
  /// mechanics, matching an `EngineTriggers.customMechanic`).
  final String id;

  /// Short human-readable name for the creator's menu.
  final String name;

  /// One-line explanation shown in the creator.
  final String description;

  /// When true, this characteristic's proficiency sets the player's GTO
  /// adherence rather than attaching a bespoke mechanic.
  final bool drivesGtoAdherence;
}

/// The known characteristics. Seeded from what exists today; extend as new
/// mechanics are authored.
const List<CharacteristicSpec> characteristicCatalog = [
  CharacteristicSpec(
    id: 'GTO_Adherence',
    name: 'GTO adherence',
    description:
        'How cleanly the player sticks to unexploitable, balanced frequencies. '
        'Proficiency sets their GTO-adherence weight (e.g. 0.92 = 92% clean).',
    drivesGtoAdherence: true,
  ),
  CharacteristicSpec(
    id: 'Soul_Read',
    name: 'Soul read',
    description:
        'Read-based gear shift: ramps postflop aggression in position when the '
        'player senses weakness. Proficiency scales how reliably it fires.',
  ),
  CharacteristicSpec(
    id: 'Geometric_Overbet_Execution',
    name: 'Geometric overbet',
    description:
        'Builds the pot with geometric overbets on later streets when holding a '
        'nut advantage. Proficiency scales sizing/consistency.',
  ),
  CharacteristicSpec(
    id: 'Positional_Warfare',
    name: 'Positional warfare',
    description:
        'Skews starting-hand selection hard by seat: much tighter in early '
        'position, much looser near the button. Proficiency scales the skew '
        '(the average number of hands played is unchanged).',
  ),
  CharacteristicSpec(
    id: 'Leverage_Pressure',
    name: 'Leverage pressure',
    description:
        'Hunts for spots to bully: ramps aggression and bluffs when heads-up, '
        'or when a bet can set the opponent all-in to continue. Proficiency '
        'scales how hard and how often the pressure fires.',
  ),
];

/// The catalog entry for [id], or null if unknown.
CharacteristicSpec? characteristicById(String id) {
  for (final c in characteristicCatalog) {
    if (c.id == id) return c;
  }
  return null;
}
