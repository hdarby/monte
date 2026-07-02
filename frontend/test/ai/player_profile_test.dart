import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/core/domain/engine/game.dart';

/// The Daniel Negreanu profile exactly as it appears in docs/personality-model.md,
/// used to prove the on-disk JSON contract parses into the model.
const _negreanuJson = {
  'id': 'P047',
  'name': 'Daniel Negreanu',
  'archetype': 'Small_Ball_Hand_Reader',
  'strategic_baseline': {
    'vpip_target': 0.26,
    'pfr_target': 0.21,
    'three_bet_frequency': 0.095,
    'gto_adherence_weight': 0.65,
  },
  'behavioral_modifiers': {
    'tilt_resistance': 0.85,
    'exploitative_weight': 0.75,
    'risk_premium_coefficient': 0.90,
    'weight_on_opponent_history': 0.90,
  },
  'engine_triggers': {
    'custom_mechanic': 'Soul_Read',
    'trigger_condition': {'in_position': true, 'min_street': 'FLOP'},
    'action_modifier': {
      'postflop_aggression_multiplier_ip': 1.30,
    },
  },
};

void main() {
  group('PlayerProfile', () {
    test('built-in profiles round-trip through JSON', () {
      for (final profile in builtInProfiles) {
        final reparsed = PlayerProfile.fromJson(profile.toJson());
        expect(
          jsonEncode(reparsed.toJson()),
          jsonEncode(profile.toJson()),
          reason: 'round-trip changed ${profile.name}',
        );
      }
    });

    test('parses the spec JSON into the typed model', () {
      final p = PlayerProfile.fromJson(_negreanuJson);
      expect(p.id, 'P047');
      expect(p.name, 'Daniel Negreanu');
      expect(p.strategicBaseline.vpipTarget, 0.26);
      expect(p.strategicBaseline.threeBetFrequency, 0.095);
      expect(p.behavioralModifiers.riskPremiumCoefficient, 0.90);
      expect(p.behavioralModifiers.weightOnOpponentHistory, 0.90);

      final t = p.engineTriggers!;
      expect(t.customMechanic, 'Soul_Read');
      expect(t.condition.inPosition, isTrue);
      expect(t.condition.minStreet, BettingRound.flop);
      expect(t.condition.hasNutAdvantage, isNull);
      expect(t.actionModifier.postflopAggressionMultiplierIp, 1.30);
      // Omitted multipliers default to neutral (1.0).
      expect(t.actionModifier.trappingFrequencyFlopTurn, 1.0);
      expect(t.actionModifier.betSizeMultiplierFlopTurnRiver, 1.0);
    });

    test('a null engine_triggers parses to no override (Haxton)', () {
      final p = PlayerProfile.fromJson(isaacHaxton.toJson());
      expect(p.engineTriggers, isNull);
      expect(p.toJson()['engine_triggers'], isNull);
    });

    test('rejects a percentage where a 0–1 fraction is required', () {
      final bad = Map<String, dynamic>.from(_negreanuJson);
      bad['strategic_baseline'] = {
        ..._negreanuJson['strategic_baseline'] as Map,
        'vpip_target': 26.0, // percentage mistake
      };
      expect(() => PlayerProfile.fromJson(bad), throwsFormatException);
    });

    test('rejects an unknown min_street', () {
      final bad = Map<String, dynamic>.from(_negreanuJson);
      bad['engine_triggers'] = {
        'trigger_condition': {'min_street': 'COSMIC'},
      };
      expect(() => PlayerProfile.fromJson(bad), throwsFormatException);
    });

    test('built-in profiles are internally consistent (PFR<=VPIP, etc.)', () {
      for (final p in builtInProfiles) {
        expect(p.validate(), isEmpty, reason: '${p.name}: ${p.validate()}');
      }
      expect(builtInProfiles.map((p) => p.id).toSet().length, 3);
    });

    test('validate() flags PFR above VPIP', () {
      const bad = PlayerProfile(
        id: 'x',
        name: 'x',
        archetype: 'x',
        strategicBaseline: StrategicBaseline(
          vpipTarget: 0.2,
          pfrTarget: 0.3, // > vpip
          threeBetFrequency: 0.05,
          gtoAdherenceWeight: 0.5,
        ),
        behavioralModifiers: BehavioralModifiers(
          tiltResistance: 0.5,
          exploitativeWeight: 0.5,
          riskPremiumCoefficient: 1.0,
          weightOnOpponentHistory: 0.5,
        ),
      );
      expect(bad.validate(), isNotEmpty);
    });
  });
}
