import 'dart:math';

/// A bot's playing style as four continuous axes in [0, 1]. Named archetypes
/// are just presets over these axes, so personalities are fully tunable.
///
/// Pure data + a risk-utility transform; no engine or framework dependencies.
class PersonalityProfile {
  const PersonalityProfile({
    this.aggression = 0.5,
    this.bluffFrequency = 0.5,
    this.tightness = 0.5,
    this.riskTolerance = 0.5,
  }) : assert(aggression >= 0 && aggression <= 1),
       assert(bluffFrequency >= 0 && bluffFrequency <= 1),
       assert(tightness >= 0 && tightness <= 1),
       assert(riskTolerance >= 0 && riskTolerance <= 1);

  /// Propensity to bet/raise rather than check/call.
  final double aggression;

  /// Propensity to bet/raise with weak hands.
  final double bluffFrequency;

  /// Selectivity entering pots — higher folds more, lowering VPIP.
  final double tightness;

  /// Appetite for variance: 0.5 is risk-neutral, below is risk-averse, above is
  /// risk-seeking. Shapes the search's payoff utility.
  final double riskTolerance;

  /// Neutral, balanced style (all axes centred).
  const PersonalityProfile.balanced() : this();

  /// Tight-aggressive: selective but bets/raises hard when in.
  const PersonalityProfile.tag()
    : this(
        aggression: 0.7,
        bluffFrequency: 0.35,
        tightness: 0.7,
        riskTolerance: 0.45,
      );

  /// Loose-aggressive: plays many hands and applies constant pressure.
  const PersonalityProfile.lag()
    : this(
        aggression: 0.8,
        bluffFrequency: 0.6,
        tightness: 0.3,
        riskTolerance: 0.6,
      );

  /// Nit: very tight and passive, rarely bluffs, avoids variance.
  const PersonalityProfile.nit()
    : this(
        aggression: 0.25,
        bluffFrequency: 0.05,
        tightness: 0.9,
        riskTolerance: 0.25,
      );

  /// Calling station: plays loose and passive, calls far too much.
  const PersonalityProfile.station()
    : this(
        aggression: 0.15,
        bluffFrequency: 0.05,
        tightness: 0.2,
        riskTolerance: 0.55,
      );

  /// Maniac: extremely loose and aggressive, bluffs constantly, loves variance.
  const PersonalityProfile.maniac()
    : this(
        aggression: 0.95,
        bluffFrequency: 0.85,
        tightness: 0.1,
        riskTolerance: 0.85,
      );

  PersonalityProfile copyWith({
    double? aggression,
    double? bluffFrequency,
    double? tightness,
    double? riskTolerance,
  }) => PersonalityProfile(
    aggression: aggression ?? this.aggression,
    bluffFrequency: bluffFrequency ?? this.bluffFrequency,
    tightness: tightness ?? this.tightness,
    riskTolerance: riskTolerance ?? this.riskTolerance,
  );

  /// Named presets over the axes, for selection in the UI and persistence.
  static const archetypes = PersonalityArchetype.values;

  /// Maps a normalized payoff in ~[-1, 1] through a constant-absolute-risk
  /// (CARA) utility curve. Risk-neutral (0.5) is the identity; risk-averse
  /// values are concave (penalize variance), risk-seeking ones convex. The
  /// transform is strictly increasing, so it never inverts an EV ordering — it
  /// only reweights how swings are valued.
  double utility(double payoff) {
    final a = (0.5 - riskTolerance) * 4.0; // >0 averse, <0 seeking, 0 neutral
    if (a.abs() < 1e-9) return payoff;
    return (1 - exp(-a * payoff)) / a;
  }
}

/// Named personality presets — the selectable archetypes.
enum PersonalityArchetype {
  balanced('Balanced'),
  tag('Tight-Aggressive'),
  lag('Loose-Aggressive'),
  nit('Nit'),
  station('Calling Station'),
  maniac('Maniac');

  const PersonalityArchetype(this.label);

  /// Human-readable name for the UI.
  final String label;

  /// The profile this archetype maps to.
  PersonalityProfile get profile => switch (this) {
    PersonalityArchetype.balanced => const PersonalityProfile.balanced(),
    PersonalityArchetype.tag => const PersonalityProfile.tag(),
    PersonalityArchetype.lag => const PersonalityProfile.lag(),
    PersonalityArchetype.nit => const PersonalityProfile.nit(),
    PersonalityArchetype.station => const PersonalityProfile.station(),
    PersonalityArchetype.maniac => const PersonalityProfile.maniac(),
  };
}
