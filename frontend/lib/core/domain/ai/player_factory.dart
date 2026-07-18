import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/player_profile.dart';

/// Pure, framework-free builders that turn creator inputs into [PlayerProfile]s.
/// All the construction logic lives here so it can be unit-tested; the
/// interactive `tool/create_player.dart` is a thin stdin shell over these.
class PlayerFactory {
  const PlayerFactory._();

  /// A recreational player. Wraps [buildAmateur] (strength → skill, style knobs)
  /// then attaches the scored [generalTraits], an [opponentReading] score
  /// (mapped onto `weightOnOpponentHistory`), and the prose [description].
  static PlayerProfile recreational({
    required String id,
    required String name,
    required int strength,
    double vpip = 0.30,
    double pfr = 0.14,
    double threeBet = 0.03,
    double exploitativeWeight = 0.30,
    double riskPremium = 1.0,
    double tiltResistance = 0.50,
    double opponentReading = 0.0,
    GeneralTraits generalTraits = const GeneralTraits(),
    String? description,
    String archetype = 'Home_Game_Amateur',
  }) {
    final base = buildAmateur(
      id: id,
      name: name,
      strength: strength,
      vpip: vpip,
      pfr: pfr,
      threeBet: threeBet,
      exploitativeWeight: exploitativeWeight,
      riskPremium: riskPremium,
      tiltResistance: tiltResistance,
      archetype: archetype,
    );
    final bm = base.behavioralModifiers;
    return PlayerProfile(
      id: base.id,
      name: base.name,
      archetype: base.archetype,
      strategicBaseline: base.strategicBaseline,
      behavioralModifiers: BehavioralModifiers(
        tiltResistance: bm.tiltResistance,
        exploitativeWeight: bm.exploitativeWeight,
        riskPremiumCoefficient: bm.riskPremiumCoefficient,
        weightOnOpponentHistory: opponentReading.clamp(0.0, 1.0),
      ),
      skill: base.skill,
      generalTraits: generalTraits,
      description: description,
    );
  }

  /// A pro. If the selected [characteristics] include `GTO_Adherence`, its
  /// proficiency overrides [gtoAdherence] (that's the "plays GTO at 92%" dial).
  static PlayerProfile pro({
    required String id,
    required String name,
    required double vpip,
    required double pfr,
    required double threeBet,
    double gtoAdherence = 0.90,
    double skill = 1.0,
    double exploitativeWeight = 0.30,
    double riskPremium = 1.0,
    double tiltResistance = 0.90,
    double opponentReading = 0.20,
    List<PlayerCharacteristic> characteristics = const [],
    GeneralTraits generalTraits = const GeneralTraits(),
    String? description,
    String archetype = 'Custom_Pro',
  }) {
    final gto = characteristics
        .where((c) => c.id == 'GTO_Adherence')
        .map((c) => c.proficiency)
        .fold<double?>(null, (_, p) => p);
    return PlayerProfile(
      id: id,
      name: name,
      archetype: archetype,
      strategicBaseline: StrategicBaseline(
        vpipTarget: vpip,
        pfrTarget: pfr,
        threeBetFrequency: threeBet,
        gtoAdherenceWeight: (gto ?? gtoAdherence).clamp(0.0, 1.0),
      ),
      behavioralModifiers: BehavioralModifiers(
        tiltResistance: tiltResistance,
        exploitativeWeight: exploitativeWeight,
        riskPremiumCoefficient: riskPremium,
        weightOnOpponentHistory: opponentReading,
      ),
      skill: skill,
      characteristics: characteristics,
      generalTraits: generalTraits,
      description: description,
    );
  }

  /// The next free `<prefix>NNN` id (e.g. `H028`, `P003`) not already in
  /// [existing]. Ids are zero-padded to three digits.
  static String nextId(String prefix, Iterable<String> existing) {
    final used = existing.toSet();
    var n = 1;
    String candidate() => '$prefix${n.toString().padLeft(3, '0')}';
    while (used.contains(candidate())) {
      n++;
    }
    return candidate();
  }
}
