import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/engine/game.dart';

/// Built-in seed profiles from `docs/personality-model.md` (the Master Archetype
/// Catalog). These are the verified profiles used to seed evaluation tables.
const List<PlayerProfile> builtInProfiles = [
  haiLe,
  michaelAddamo,
  isaacHaxton,
];

/// Profile A — The High-Stakes Positional Trapper.
const haiLe = PlayerProfile(
  id: 'P047',
  name: 'Hai Le',
  archetype: 'Lag_Positional_Trapper',
  strategicBaseline: StrategicBaseline(
    vpipTarget: 0.26,
    pfrTarget: 0.21,
    threeBetFrequency: 0.095,
    gtoAdherenceWeight: 0.65,
  ),
  behavioralModifiers: BehavioralModifiers(
    tiltResistance: 0.85,
    exploitativeWeight: 0.75,
    riskPremiumCoefficient: 0.90,
    weightOnOpponentHistory: 0.80,
  ),
  engineTriggers: EngineTriggers(
    customMechanic: 'Positional_Leverage_Trap',
    condition: TriggerCondition(
      inPosition: true,
      minStreet: BettingRound.flop,
    ),
    actionModifier: ActionModifier(
      trappingFrequencyFlopTurn: 1.50,
      postflopAggressionMultiplierIp: 1.30,
    ),
  ),
);

/// Profile B — The Geometric Overbet Maximizer.
const michaelAddamo = PlayerProfile(
  id: 'P041',
  name: 'Michael Addamo',
  archetype: 'Hyper_Aggressive_Elite',
  strategicBaseline: StrategicBaseline(
    vpipTarget: 0.32,
    pfrTarget: 0.28,
    threeBetFrequency: 0.14,
    gtoAdherenceWeight: 0.80,
  ),
  behavioralModifiers: BehavioralModifiers(
    tiltResistance: 0.99,
    exploitativeWeight: 0.60,
    riskPremiumCoefficient: 1.50,
    weightOnOpponentHistory: 0.50,
  ),
  engineTriggers: EngineTriggers(
    customMechanic: 'Geometric_Overbet_Execution',
    condition: TriggerCondition(
      minStreet: BettingRound.turn,
      hasNutAdvantage: true,
    ),
    actionModifier: ActionModifier(betSizeMultiplierFlopTurnRiver: 2.50),
  ),
);

/// Profile C — The Pure GTO Anchor.
const isaacHaxton = PlayerProfile(
  id: 'P001',
  name: 'Isaac Haxton',
  archetype: 'GTO_Wizard',
  strategicBaseline: StrategicBaseline(
    vpipTarget: 0.24,
    pfrTarget: 0.195,
    threeBetFrequency: 0.08,
    gtoAdherenceWeight: 1.00,
  ),
  behavioralModifiers: BehavioralModifiers(
    tiltResistance: 1.00,
    exploitativeWeight: 0.00,
    riskPremiumCoefficient: 1.00,
    weightOnOpponentHistory: 0.00,
  ),
);
