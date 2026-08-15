import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/features/tournament/domain/field_builder.dart';

/// The buy-in dial. Nobody plays a $10,000 seat the way they play a $100 one,
/// and a $10,000 field is not drawn from the same pool of players. Both halves
/// are modelled — a given player tightens and sharpens ([PlayerProfile.atStakes])
/// and the field itself gets tougher ([FieldBuilder.build]).
void main() {
  group('stakes pressure scales with the buy-in', () {
    test('runs 0 at a cheap event to 1 at the Main Event', () {
      expect(FieldBuilder.stakesPressure(11), 0.0);
      expect(FieldBuilder.stakesPressure(100), 0.0);
      expect(FieldBuilder.stakesPressure(10000), 1.0);
      expect(FieldBuilder.stakesPressure(25000), 1.0);
    });

    test('is log-scaled: the first tenfold step matters most', () {
      final low = FieldBuilder.stakesPressure(1000) -
          FieldBuilder.stakesPressure(100);
      final high = FieldBuilder.stakesPressure(10000) -
          FieldBuilder.stakesPressure(1000);
      expect(low, closeTo(high, 0.05),
          reason: 'each tenfold step should be worth about the same');
      expect(FieldBuilder.stakesPressure(1000), closeTo(0.5, 0.05));
    });
  });

  group('a player at a big buy-in', () {
    final base = danielNegreanu;
    final main = base.atStakes(1.0);

    test('plays fewer hands', () {
      expect(main.strategicBaseline.vpipTarget,
          lessThan(base.strategicBaseline.vpipTarget));
    });

    test('but plays them harder — the aggression dial goes up', () {
      double aggression(p) =>
          p.strategicBaseline.pfrTarget / p.strategicBaseline.vpipTarget;
      expect(aggression(main), greaterThan(aggression(base)),
          reason: 'a larger share of entered hands should be raised');
      expect(main.strategicBaseline.threeBetFrequency,
          greaterThan(base.strategicBaseline.threeBetFrequency));
    });

    test('makes fewer mistakes and sizes more carefully', () {
      expect(main.strategicBaseline.gtoAdherenceWeight,
          greaterThan(base.strategicBaseline.gtoAdherenceWeight));
      expect(main.skill, greaterThanOrEqualTo(base.skill));
      expect(main.behavioralModifiers.riskPremiumCoefficient,
          lessThan(base.behavioralModifiers.riskPremiumCoefficient));
    });

    test('keeps its identity — this is the same person, not a new one', () {
      expect(main.id, base.id);
      expect(main.name, base.name);
      expect(main.characteristics, base.characteristics);
    });

    test('zero pressure is exactly a no-op', () {
      final same = base.atStakes(0);
      expect(same.strategicBaseline.vpipTarget,
          base.strategicBaseline.vpipTarget);
      expect(same.skill, base.skill);
    });

    test('preflop targets stay a nested, feasible set', () {
      for (final p in [...builtInProfiles.take(6)]) {
        for (final t in [0.0, 0.5, 1.0]) {
          final b = p.atStakes(t).strategicBaseline;
          expect(b.pfrTarget, lessThanOrEqualTo(b.vpipTarget));
          expect(b.threeBetFrequency, lessThanOrEqualTo(b.pfrTarget));
          expect(b.vpipTarget, greaterThan(0));
        }
      }
    });
  });

  group('the field itself gets tougher', () {
    List<String> fieldAt(int buyIn) => FieldBuilder(
          humanName: 'You',
          rng: Random(4),
        ).build(selectedIds: const {}, entrants: 60, buyIn: buyIn).map((p) => p.id).toList();

    test('a Main Event field is drawn more heavily from pros', () {
      final proIds = builtInProfiles.map((p) => p.id).toSet();
      int pros(List<String> ids) => ids.where(proIds.contains).length;

      final cheap = fieldAt(100);
      final main = fieldAt(10000);
      expect(pros(main), greaterThan(pros(cheap)),
          reason: 'a \$10k field should have fewer recreational players');
    });

    test('a cheap event is unchanged from the no-buy-in default', () {
      final none = FieldBuilder(humanName: 'You', rng: Random(4))
          .build(selectedIds: const {}, entrants: 60);
      final cheap = FieldBuilder(humanName: 'You', rng: Random(4))
          .build(selectedIds: const {}, entrants: 60, buyIn: 100);
      expect(cheap.map((p) => p.id), none.map((p) => p.id));
    });
  });
}
