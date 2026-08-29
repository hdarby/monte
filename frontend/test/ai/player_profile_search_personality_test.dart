import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/player_profile.dart';

PlayerProfile _profile({
  required double vpip,
  required double pfr,
  double threeBet = 0.08,
  double gtoAdherenceWeight = 0.5,
  double exploitativeWeight = 0.5,
  double riskPremiumCoefficient = 1.0,
}) =>
    PlayerProfile(
      id: 'p',
      name: 'P',
      archetype: 'test',
      strategicBaseline: StrategicBaseline(
        vpipTarget: vpip,
        pfrTarget: pfr,
        threeBetFrequency: threeBet,
        gtoAdherenceWeight: gtoAdherenceWeight,
      ),
      behavioralModifiers: BehavioralModifiers(
        tiltResistance: 0.5,
        exploitativeWeight: exploitativeWeight,
        riskPremiumCoefficient: riskPremiumCoefficient,
        weightOnOpponentHistory: 0.5,
      ),
    );

void main() {
  group('PlayerProfile.toPersonalityProfile', () {
    test('a tight, low-pfr:vpip player maps to high tightness, low '
        'aggression — a nit-like search personality', () {
      final p = _profile(vpip: 0.14, pfr: 0.11).toPersonalityProfile();
      expect(p.tightness, greaterThan(0.8));
      expect(p.aggression, lessThan(0.85));
    });

    test('a loose, high-pfr:vpip player maps to low tightness, high '
        'aggression — a LAG-like search personality', () {
      final p = _profile(vpip: 0.45, pfr: 0.38).toPersonalityProfile();
      expect(p.tightness, lessThan(0.6));
      expect(p.aggression, greaterThan(0.7));
    });

    test('a station (high vpip, low pfr) maps to low aggression despite '
        'playing many hands', () {
      final p = _profile(vpip: 0.45, pfr: 0.08).toPersonalityProfile();
      expect(p.tightness, lessThan(0.6));
      expect(p.aggression, lessThan(0.3));
    });

    test('riskPremiumCoefficient at its floor (0.6) maps to risk-averse '
        '(tightness of risk, not hand selection)', () {
      final p =
          _profile(vpip: 0.25, pfr: 0.18, riskPremiumCoefficient: 0.6)
              .toPersonalityProfile();
      expect(p.riskTolerance, 0.0);
    });

    test('riskPremiumCoefficient at its ceiling (1.6) maps to risk-seeking',
        () {
      final p =
          _profile(vpip: 0.25, pfr: 0.18, riskPremiumCoefficient: 1.6)
              .toPersonalityProfile();
      expect(p.riskTolerance, 1.0);
    });

    test('a strictly GTO-adherent player bluffs less than an equally '
        'aggressive exploitative one', () {
      final gto = _profile(
        vpip: 0.30,
        pfr: 0.24,
        gtoAdherenceWeight: 1.0,
        exploitativeWeight: 0.9,
      ).toPersonalityProfile();
      final exploit = _profile(
        vpip: 0.30,
        pfr: 0.24,
        gtoAdherenceWeight: 0.1,
        exploitativeWeight: 0.9,
      ).toPersonalityProfile();
      expect(gto.bluffFrequency, lessThan(exploit.bluffFrequency));
    });

    test('every field stays within the valid [0,1] PersonalityProfile range '
        'across a wide input sweep', () {
      for (var vpip = 0.05; vpip <= 0.95; vpip += 0.15) {
        for (var pfr = 0.02; pfr <= vpip; pfr += 0.15) {
          for (final risk in [0.1, 0.6, 1.0, 1.6, 3.0]) {
            final p = _profile(
              vpip: vpip,
              pfr: pfr,
              riskPremiumCoefficient: risk,
            ).toPersonalityProfile();
            for (final v in [
              p.aggression,
              p.bluffFrequency,
              p.tightness,
              p.riskTolerance,
            ]) {
              expect(v, inInclusiveRange(0.0, 1.0));
            }
          }
        }
      }
    });
  });
}
