import 'package:meta/meta.dart';

import 'package:monte/core/domain/engine/game.dart';

/// A full simulated-player profile: a poker-native *style* baseline, *skill /
/// behavioral* modifiers, and optional situational *engine triggers*.
///
/// This is the Phase 0 data contract from `docs/personality-model.md` — pure
/// data with JSON (de)serialization and range validation, not yet wired into the
/// decision engine. Conventions: frequencies/weights are 0–1 fractions;
/// multipliers (`riskPremiumCoefficient`, `ActionModifier.*`) are centred on 1.0.
@immutable
class PlayerProfile {
  const PlayerProfile({
    required this.id,
    required this.name,
    required this.archetype,
    required this.strategicBaseline,
    required this.behavioralModifiers,
    this.engineTriggers,
    this.skill = 1.0,
  }) : assert(skill >= 0 && skill <= 1);

  final String id;
  final String name;
  final String archetype;
  final StrategicBaseline strategicBaseline;
  final BehavioralModifiers behavioralModifiers;

  /// Null when the profile has no situational override.
  final EngineTriggers? engineTriggers;

  /// Execution quality in [0, 1]: 1.0 = flawless (pro-tier), lower = noisier
  /// hand reads, looser discipline, and the occasional blunder. The single dial
  /// separating amateurs from pros; every amateur leak scales with `1 - skill`,
  /// so `skill == 1` plays byte-identically to the disciplined pro brain.
  /// Defaults to 1.0 so existing pro profiles (and their JSON) are unchanged.
  final double skill;

  factory PlayerProfile.fromJson(Map<String, dynamic> json) => PlayerProfile(
    id: _str(json, 'id'),
    name: _str(json, 'name'),
    archetype: _str(json, 'archetype'),
    strategicBaseline: StrategicBaseline.fromJson(_obj(json, 'strategic_baseline')),
    behavioralModifiers: BehavioralModifiers.fromJson(
      _obj(json, 'behavioral_modifiers'),
    ),
    engineTriggers: json['engine_triggers'] == null
        ? null
        : EngineTriggers.fromJson(_obj(json, 'engine_triggers')),
    // Optional: older profiles predate `skill` and default to pro-tier 1.0.
    skill: _unitOr(json, 'skill', 1.0),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'archetype': archetype,
    'strategic_baseline': strategicBaseline.toJson(),
    'behavioral_modifiers': behavioralModifiers.toJson(),
    'engine_triggers': engineTriggers?.toJson(),
    'skill': skill,
  };

  /// Soft, cross-field sanity checks (each entry is a human-readable warning).
  /// Hard range/scale errors are caught at parse time by [fromJson].
  List<String> validate() {
    final w = <String>[];
    final b = strategicBaseline;
    if (b.pfrTarget > b.vpipTarget) {
      w.add('PFR target (${b.pfrTarget}) exceeds VPIP target (${b.vpipTarget}).');
    }
    if (b.threeBetFrequency > b.pfrTarget) {
      w.add('3-bet frequency (${b.threeBetFrequency}) exceeds PFR (${b.pfrTarget}).');
    }
    return w;
  }
}

/// Poker-native *style* targets — what the player tends to do.
@immutable
class StrategicBaseline {
  const StrategicBaseline({
    required this.vpipTarget,
    required this.pfrTarget,
    required this.threeBetFrequency,
    required this.gtoAdherenceWeight,
  }) : assert(vpipTarget >= 0 && vpipTarget <= 1),
       assert(pfrTarget >= 0 && pfrTarget <= 1),
       assert(threeBetFrequency >= 0 && threeBetFrequency <= 1),
       assert(gtoAdherenceWeight >= 0 && gtoAdherenceWeight <= 1);

  /// Voluntarily-put-money-in-pot frequency (0–1).
  final double vpipTarget;

  /// Preflop-raise frequency (0–1).
  final double pfrTarget;

  /// 3-bet frequency (0–1).
  final double threeBetFrequency;

  /// How rigidly the player sticks to unexploitable frequencies (0–1; 1.0 =
  /// ignore opponent tendencies entirely).
  final double gtoAdherenceWeight;

  factory StrategicBaseline.fromJson(Map<String, dynamic> j) => StrategicBaseline(
    vpipTarget: _unit(j, 'vpip_target'),
    pfrTarget: _unit(j, 'pfr_target'),
    threeBetFrequency: _unit(j, 'three_bet_frequency'),
    gtoAdherenceWeight: _unit(j, 'gto_adherence_weight'),
  );

  Map<String, dynamic> toJson() => {
    'vpip_target': vpipTarget,
    'pfr_target': pfrTarget,
    'three_bet_frequency': threeBetFrequency,
    'gto_adherence_weight': gtoAdherenceWeight,
  };
}

/// *Skill / psychology* modifiers — how well and how steadily the player plays.
@immutable
class BehavioralModifiers {
  const BehavioralModifiers({
    required this.tiltResistance,
    required this.exploitativeWeight,
    required this.riskPremiumCoefficient,
    required this.weightOnOpponentHistory,
  }) : assert(tiltResistance >= 0 && tiltResistance <= 1),
       assert(exploitativeWeight >= 0 && exploitativeWeight <= 1),
       assert(riskPremiumCoefficient >= 0),
       assert(weightOnOpponentHistory >= 0 && weightOnOpponentHistory <= 1);

  /// Resistance to tilt after losses (0–1).
  final double tiltResistance;

  /// Inclination to deviate from baseline to attack opponent imbalances (0–1).
  final double exploitativeWeight;

  /// Variance appetite as a multiplier centred on 1.0 (>1 seeks variance).
  final double riskPremiumCoefficient;

  /// How much observed opponent history informs decisions (0–1).
  final double weightOnOpponentHistory;

  factory BehavioralModifiers.fromJson(Map<String, dynamic> j) =>
      BehavioralModifiers(
        tiltResistance: _unit(j, 'tilt_resistance'),
        exploitativeWeight: _unit(j, 'exploitative_weight'),
        riskPremiumCoefficient: _mult(j, 'risk_premium_coefficient'),
        weightOnOpponentHistory: _unit(j, 'weight_on_opponent_history'),
      );

  Map<String, dynamic> toJson() => {
    'tilt_resistance': tiltResistance,
    'exploitative_weight': exploitativeWeight,
    'risk_premium_coefficient': riskPremiumCoefficient,
    'weight_on_opponent_history': weightOnOpponentHistory,
  };
}

/// A situational override: a named mechanic, the [condition] that arms it, and
/// the [actionModifier] it applies.
@immutable
class EngineTriggers {
  const EngineTriggers({
    this.customMechanic,
    required this.condition,
    required this.actionModifier,
  });

  /// Identifier for the bespoke mechanic (e.g. `Soul_Read`).
  final String? customMechanic;
  final TriggerCondition condition;
  final ActionModifier actionModifier;

  factory EngineTriggers.fromJson(Map<String, dynamic> j) => EngineTriggers(
    customMechanic: j['custom_mechanic'] as String?,
    condition: TriggerCondition.fromJson(
      (j['trigger_condition'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    actionModifier: ActionModifier.fromJson(
      (j['action_modifier'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
  );

  Map<String, dynamic> toJson() => {
    'custom_mechanic': customMechanic,
    'trigger_condition': condition.toJson(),
    'action_modifier': actionModifier.toJson(),
  };
}

/// A structured predicate set. Present keys are ANDed; omitted keys mean "don't
/// care". (Evaluation against live game state lands in Phase 4.)
@immutable
class TriggerCondition {
  const TriggerCondition({
    this.inPosition,
    this.minStreet,
    this.hasNutAdvantage,
  });

  final bool? inPosition;

  /// Matches this street or later (PREFLOP/FLOP/TURN/RIVER).
  final BettingRound? minStreet;
  final bool? hasNutAdvantage;

  bool get isEmpty =>
      inPosition == null && minStreet == null && hasNutAdvantage == null;

  factory TriggerCondition.fromJson(Map<String, dynamic> j) => TriggerCondition(
    inPosition: j['in_position'] as bool?,
    minStreet: _streetFromJson(j['min_street']),
    hasNutAdvantage: j['has_nut_advantage'] as bool?,
  );

  Map<String, dynamic> toJson() => {
    if (inPosition != null) 'in_position': inPosition,
    if (minStreet != null) 'min_street': _streetToJson(minStreet!),
    if (hasNutAdvantage != null) 'has_nut_advantage': hasNutAdvantage,
  };
}

/// Multipliers (centred on 1.0) applied when an [EngineTriggers] fires.
@immutable
class ActionModifier {
  const ActionModifier({
    this.trappingFrequencyFlopTurn = 1.0,
    this.postflopAggressionMultiplierIp = 1.0,
    this.betSizeMultiplierFlopTurnRiver = 1.0,
  }) : assert(trappingFrequencyFlopTurn >= 0),
       assert(postflopAggressionMultiplierIp >= 0),
       assert(betSizeMultiplierFlopTurnRiver >= 0);

  final double trappingFrequencyFlopTurn;
  final double postflopAggressionMultiplierIp;
  final double betSizeMultiplierFlopTurnRiver;

  factory ActionModifier.fromJson(Map<String, dynamic> j) => ActionModifier(
    trappingFrequencyFlopTurn: _mult(j, 'trapping_frequency_flop_turn'),
    postflopAggressionMultiplierIp: _mult(j, 'postflop_aggression_multiplier_ip'),
    betSizeMultiplierFlopTurnRiver: _mult(j, 'bet_size_multiplier_flop_turn_river'),
  );

  Map<String, dynamic> toJson() => {
    'trapping_frequency_flop_turn': trappingFrequencyFlopTurn,
    'postflop_aggression_multiplier_ip': postflopAggressionMultiplierIp,
    'bet_size_multiplier_flop_turn_river': betSizeMultiplierFlopTurnRiver,
  };
}

// ---- Parse helpers ----------------------------------------------------------

String _str(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v is! String || v.isEmpty) {
    throw FormatException('Missing/invalid string field "$key".');
  }
  return v;
}

Map<String, dynamic> _obj(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v is! Map) throw FormatException('Missing object field "$key".');
  return v.cast<String, dynamic>();
}

/// A 0–1 fraction. Rejects percentages (e.g. `26.0`), the classic units mistake.
double _unit(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v is! num) throw FormatException('Field "$key" must be a number.');
  final d = v.toDouble();
  if (d < 0 || d > 1) {
    throw FormatException('Field "$key" must be a 0–1 fraction (got $d).');
  }
  return d;
}

/// A 0–1 fraction that defaults to [fallback] when the key is absent (unlike
/// [_unit], which requires it). Rejects percentages when present.
double _unitOr(Map<String, dynamic> j, String key, double fallback) {
  if (j[key] == null) return fallback;
  return _unit(j, key);
}

/// A multiplier centred on 1.0; defaults to 1.0 when absent. Must be >= 0.
double _mult(Map<String, dynamic> j, String key, {double fallback = 1.0}) {
  final v = j[key];
  if (v == null) return fallback;
  if (v is! num) throw FormatException('Field "$key" must be a number.');
  final d = v.toDouble();
  if (d < 0) throw FormatException('Field "$key" must be >= 0 (got $d).');
  return d;
}

const _streets = [
  BettingRound.preflop,
  BettingRound.flop,
  BettingRound.turn,
  BettingRound.river,
];

BettingRound? _streetFromJson(Object? v) {
  if (v == null) return null;
  final s = v.toString().toLowerCase();
  for (final r in _streets) {
    if (r.name == s) return r;
  }
  throw FormatException('Unknown min_street "$v".');
}

String _streetToJson(BettingRound r) => r.name.toUpperCase();
