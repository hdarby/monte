import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/personality.dart';

void main() {
  group('PersonalityProfile archetypes', () {
    test('tightness is ordered nit > tag > lag > maniac', () {
      expect(
        const PersonalityProfile.nit().tightness,
        greaterThan(const PersonalityProfile.tag().tightness),
      );
      expect(
        const PersonalityProfile.tag().tightness,
        greaterThan(const PersonalityProfile.lag().tightness),
      );
      expect(
        const PersonalityProfile.lag().tightness,
        greaterThan(const PersonalityProfile.maniac().tightness),
      );
    });

    test('aggression is ordered maniac > lag > tag > station', () {
      expect(
        const PersonalityProfile.maniac().aggression,
        greaterThan(const PersonalityProfile.lag().aggression),
      );
      expect(
        const PersonalityProfile.lag().aggression,
        greaterThan(const PersonalityProfile.tag().aggression),
      );
      expect(
        const PersonalityProfile.tag().aggression,
        greaterThan(const PersonalityProfile.station().aggression),
      );
    });

    test('maniac bluffs far more than a nit', () {
      expect(
        const PersonalityProfile.maniac().bluffFrequency,
        greaterThan(const PersonalityProfile.nit().bluffFrequency),
      );
    });

    test('axes are validated to [0, 1]', () {
      expect(() => PersonalityProfile(aggression: 1.5), throwsA(anything));
      expect(() => PersonalityProfile(tightness: -0.1), throwsA(anything));
    });
  });

  group('PersonalityProfile.utility', () {
    test('is the identity when risk-neutral', () {
      const p = PersonalityProfile.balanced();
      expect(p.utility(0.4), closeTo(0.4, 1e-9));
      expect(p.utility(-0.7), closeTo(-0.7, 1e-9));
    });

    test('is strictly increasing for every risk level', () {
      for (final p in const [
        PersonalityProfile.nit(), // risk-averse
        PersonalityProfile.balanced(), // neutral
        PersonalityProfile.maniac(), // risk-seeking
      ]) {
        expect(p.utility(-0.5), lessThan(p.utility(0)));
        expect(p.utility(0), lessThan(p.utility(0.5)));
      }
    });

    test('risk-averse dislikes a symmetric gamble; risk-seeking likes it', () {
      double gambleValue(PersonalityProfile p) =>
          (p.utility(0.5) + p.utility(-0.5)) / 2; // vs utility(0) == 0

      expect(gambleValue(const PersonalityProfile.nit()), lessThan(0));
      expect(
        gambleValue(const PersonalityProfile.balanced()),
        closeTo(0, 1e-9),
      );
      expect(gambleValue(const PersonalityProfile.maniac()), greaterThan(0));
    });
  });
}
