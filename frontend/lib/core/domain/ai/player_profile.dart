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
    this.generalTraits = const GeneralTraits(),
    this.characteristics = const [],
    this.description,
    this.generated = false,
  }) : assert(skill >= 0 && skill <= 1);

  final String id;
  final String name;

  /// True for an anonymous auto-filled field seat (a personality's *style* worn
  /// under a fictitious name to complete a tournament). Generated players are
  /// ephemeral — they build no persistent read and hold no read of anyone, so
  /// they're excluded from the reads book. Only real, named personalities (and
  /// the human) accumulate reads that persist across sessions.
  final bool generated;
  final String archetype;
  final StrategicBaseline strategicBaseline;
  final BehavioralModifiers behavioralModifiers;

  /// Null when the profile has no situational override.
  final EngineTriggers? engineTriggers;

  /// Broad, human-scored poker skills every player (pro or rec) is rated on.
  /// Captured data for display and future wiring (see [GeneralTraits]).
  final GeneralTraits generalTraits;

  /// The special characteristics (from the catalog) this player uses, each with
  /// a 0–1 proficiency. Empty for players with no bespoke mechanics.
  final List<PlayerCharacteristic> characteristics;

  /// Free-text prose describing how the player plays (a pro's write-up, or a
  /// rec's strengths/weaknesses). Null when unset; [archetype] stays the label.
  final String? description;

  /// Proficiency (0–1) of the characteristic with [id], or 0 if the player
  /// doesn't have it. Lets a decision policy read a bespoke mechanic's strength
  /// without hand-rolling the lookup.
  double proficiencyOf(String id) {
    for (final c in characteristics) {
      if (c.id == id) return c.proficiency;
    }
    return 0.0;
  }

  /// A copy with a different display [name] — used to seat a personality under a
  /// fictitious identity (e.g. an auto-filled tournament entrant) while keeping
  /// its id, skill and every stat, so it plays identically. Pass
  /// [generated] = true for an anonymous field-filler (see [generated]).
  PlayerProfile renamed(String name, {bool generated = false}) => PlayerProfile(
        id: id,
        name: name,
        archetype: archetype,
        strategicBaseline: strategicBaseline,
        behavioralModifiers: behavioralModifiers,
        engineTriggers: engineTriggers,
        skill: skill,
        generalTraits: generalTraits,
        characteristics: characteristics,
        description: description,
        generated: generated,
      );

  /// A copy with [strategicBaseline] replaced — used to apply a tuned baseline
  /// override while keeping the profile's identity, skill, and modifiers.
  PlayerProfile withStrategicBaseline(StrategicBaseline baseline) =>
      PlayerProfile(
        id: id,
        name: name,
        archetype: archetype,
        strategicBaseline: baseline,
        behavioralModifiers: behavioralModifiers,
        engineTriggers: engineTriggers,
        skill: skill,
        generalTraits: generalTraits,
        characteristics: characteristics,
        description: description,
      );

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
    // Optional additive blocks — absent in older profiles.
    generalTraits: json['general_traits'] == null
        ? const GeneralTraits()
        : GeneralTraits.fromJson(_obj(json, 'general_traits')),
    characteristics: [
      for (final c in (json['characteristics'] as List?) ?? const [])
        PlayerCharacteristic.fromJson((c as Map).cast<String, dynamic>()),
    ],
    description: json['description'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'archetype': archetype,
    'strategic_baseline': strategicBaseline.toJson(),
    'behavioral_modifiers': behavioralModifiers.toJson(),
    'engine_triggers': engineTriggers?.toJson(),
    'skill': skill,
    'general_traits': generalTraits.toJson(),
    'characteristics': [for (final c in characteristics) c.toJson()],
    'description': description,
  };

  /// Whether a set of preflop targets is *reachable* by the closed-loop
  /// calibrator at 6-max, returning human-readable violations (empty = OK). A
  /// deliberately conservative guide for the creator tool: it steers new pros
  /// into the safe zone, so it may flag a borderline combo that would just
  /// squeak through (a very low PFR tolerates a smaller open, for instance).
  ///
  /// The envelope is grounded in the built-in pros that pass
  /// `profile_calibration_test` and in how the no-open-limp policy realises
  /// frequencies: PFR = opens + 3-bets (so the open range PFR−3-bet must be real
  /// or PFR undershoots), and VPIP = opens + flats (so the VPIP−PFR gap must be
  /// real or VPIP overshoots). 3-bets above ~0.14 can't be realised at 6-max.
  static List<String> preflopFeasibility({
    required double vpip,
    required double pfr,
    required double threeBet,
  }) {
    final v = <String>[];
    if (threeBet > pfr) {
      v.add('3-bet ($threeBet) exceeds PFR ($pfr).');
    }
    if (pfr > vpip) {
      v.add('PFR ($pfr) exceeds VPIP ($vpip).');
    }
    const eps = 1e-9; // tolerate float boundaries (0.18-0.10 != exactly 0.08)
    if (threeBet > 0.14 + eps) {
      v.add('3-bet ($threeBet) above 0.14 — not reachable at 6-max; cap ~0.14.');
    }
    final open = pfr - threeBet;
    if (open < 0.08 - eps) {
      v.add('Open range PFR−3-bet (${open.toStringAsFixed(2)}) below 0.08 — PFR '
          'collapses (too few opens). Raise PFR or lower 3-bet.');
    }
    final gap = vpip - pfr;
    if (gap < 0.06 - eps) {
      v.add('VPIP−PFR gap (${gap.toStringAsFixed(2)}) below 0.06 — VPIP '
          'overshoots (opens+flats exceed it). Raise VPIP or lower PFR.');
    }
    if (vpip < 0.10 - eps || vpip > 0.55 + eps) {
      v.add('VPIP ($vpip) outside the reachable 0.10–0.55 range.');
    }
    return v;
  }

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
    final ids = characteristics.map((c) => c.id).toList();
    if (ids.toSet().length != ids.length) {
      w.add('Duplicate characteristic ids: $ids.');
    }
    return w;
  }
}

/// Broad poker skills every player is scored on, each a 0–1 proficiency. These
/// are captured for display and future wiring; tilt control and opponent reading
/// live on [BehavioralModifiers] (`tiltResistance` / `weightOnOpponentHistory`)
/// to avoid a second source of truth, so only the genuinely-new dimensions are
/// here.
@immutable
class GeneralTraits {
  const GeneralTraits({
    this.positionAwareness = 0.5,
    this.potOdds = 0.5,
    this.impliedOdds = 0.5,
  })  : assert(positionAwareness >= 0 && positionAwareness <= 1),
        assert(potOdds >= 0 && potOdds <= 1),
        assert(impliedOdds >= 0 && impliedOdds <= 1);

  /// Awareness of position when choosing hands and lines (0–1).
  final double positionAwareness;

  /// Grasp of immediate pot odds (0–1).
  final double potOdds;

  /// Grasp of implied odds — future streets' payoff on draws (0–1).
  final double impliedOdds;

  factory GeneralTraits.fromJson(Map<String, dynamic> j) => GeneralTraits(
        positionAwareness: _unitOr(j, 'position_awareness', 0.5),
        potOdds: _unitOr(j, 'pot_odds', 0.5),
        impliedOdds: _unitOr(j, 'implied_odds', 0.5),
      );

  Map<String, dynamic> toJson() => {
        'position_awareness': positionAwareness,
        'pot_odds': potOdds,
        'implied_odds': impliedOdds,
      };
}

/// One special characteristic (by catalog [id]) a player uses, and how well
/// ([proficiency], 0–1). E.g. `GTO_Adherence` at 0.92 = plays GTO 92% cleanly.
@immutable
class PlayerCharacteristic {
  const PlayerCharacteristic({required this.id, this.proficiency = 1.0})
      : assert(proficiency >= 0 && proficiency <= 1);

  final String id;
  final double proficiency;

  factory PlayerCharacteristic.fromJson(Map<String, dynamic> j) =>
      PlayerCharacteristic(
        id: _str(j, 'id'),
        proficiency: _unitOr(j, 'proficiency', 1.0),
      );

  Map<String, dynamic> toJson() => {'id': id, 'proficiency': proficiency};
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
