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
    id: 'Tilt_Blowup',
    name: 'Blow-up tilt',
    description:
        'After a big loss they come out swinging — far more hands, played far '
        'harder. Proficiency scales how violently. Needs tilt resistance low '
        'enough for the pressure to build in the first place.',
  ),
  CharacteristicSpec(
    id: 'Tilt_Chase',
    name: 'Chasing tilt',
    description:
        'After a big loss they get sticky rather than aggressive: more hands, '
        'fewer raises, and they call down to prove a point. Proficiency scales '
        'how far.',
  ),
  CharacteristicSpec(
    id: 'Tilt_Shutdown',
    name: 'Shutdown tilt',
    description:
        'After a big loss they go into a shell and wait for a monster — the '
        'reaction nobody models, because tilt is assumed to mean aggression. '
        'Proficiency scales how tightly they clam up.',
  ),
  CharacteristicSpec(
    id: 'Check_Raise_Merchant',
    name: 'Check-raise merchant',
    description:
        'Checks strong hands and draws out of position intending to raise, and '
        'follows through far more often than a baseline player. Proficiency '
        'scales both halves.',
  ),
  CharacteristicSpec(
    id: 'Slow_Play_Trap',
    name: 'Slow-play trap',
    description:
        'Checks or flats a big made hand instead of betting it, then springs '
        'the trap on a later street. Proficiency scales how often they take '
        'the passive line with a monster.',
  ),
  CharacteristicSpec(
    id: 'Sticky_Showdown',
    name: 'Sticky showdown',
    description:
        'Will not fold a made hand. Once they hold top pair or better they '
        'call down far wider than the price justifies. Proficiency scales how '
        'much of the normal fold discipline they give up.',
  ),
  CharacteristicSpec(
    id: 'Float_And_Take_Away',
    name: 'Float and take it away',
    description:
        'Calls a flop bet in position with little or nothing, then bets when '
        'the aggressor checks the turn. Proficiency scales how often the '
        'follow-through fires.',
  ),
  CharacteristicSpec(
    id: 'Bubble_Predator',
    name: 'Bubble predator',
    description:
        'Attacks opponents who cannot afford to call — ramps aggression as '
        'ICM pressure rises near a pay jump. Proficiency scales how hard.',
  ),
  CharacteristicSpec(
    id: 'Limp_Reraise',
    name: 'Limp re-raise',
    description:
        'Old-school: limps a premium from early position hoping someone '
        'raises, then comes over the top. Proficiency scales how often a '
        'premium is limped rather than opened.',
  ),
  CharacteristicSpec(
    id: 'Underbluff_Exploit',
    name: 'Underbluff exploit',
    description:
        'Folds marginal bluff-catchers to river bets from recreational '
        'players, who almost never bluff the end. Proficiency scales how '
        'strongly the read is trusted.',
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
