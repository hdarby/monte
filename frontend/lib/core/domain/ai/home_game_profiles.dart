import 'package:monte/core/domain/ai/player_profile.dart';

/// The owner's home-game amateurs — weaker, mistake-prone players built on the
/// same profile model as the pros but with `skill < 1.0`, so they play the
/// degraded [AmateurPolicy] brain and reliably lose to the pros.
///
/// Each is one [buildAmateur] entry: a strength rating (1–10 → `skill`) plus
/// style stats. Style is expressed through real poker numbers so it drives the
/// brain: `vpip`/`pfr`/`threeBet` shape the preflop game (a big VPIP≫PFR gap
/// reads as loose-passive/limpy; low VPIP as a nit), `exploitativeWeight` is the
/// bluff/pressure appetite ("never bluffs" ≈ 0.1, LAG ≈ 0.65+), and `riskPremium`
/// is the bet-sizing swing (min-raiser/small value ≈ 0.8–0.9, big LAG ≈ 1.25).
final List<PlayerProfile> homeGameProfiles = [
  daveMiller,
  dougNiemec,
  jasonDouglas,
  mattRosen,
  frankDouglas,
  mitch,
  patWray,
  philDiPinto,
  robGustine,
  ramseyYeheah,
  justinVidovitch,
  haiLe,
  johnPineta,
];

/// Maps the owner's 1–10 strength rating to the internal `skill` dial in
/// `[0, 1]`. 10 (strong amateur, near-pro) ≈ 0.88; 1 (beginner) ≈ 0.12. Always
/// strictly below a pro's 1.0. Tune here if the rating scale changes.
double strengthToSkill(int strength) =>
    (0.12 + 0.084 * (strength.clamp(1, 10) - 1)).clamp(0.05, 0.95);

/// Builds an amateur profile from a strength rating (1–10) and style knobs.
/// `skill` (from [strength]) governs execution quality; `gtoAdherenceWeight`
/// rises with skill but stays below the pros' 1.0.
PlayerProfile buildAmateur({
  required String id,
  required String name,
  required int strength,
  double vpip = 0.30,
  double pfr = 0.14,
  double threeBet = 0.03,
  double exploitativeWeight = 0.30,
  double riskPremium = 1.0,
  double tiltResistance = 0.50,
  String archetype = 'Home_Game_Amateur',
}) {
  final skill = strengthToSkill(strength);
  return PlayerProfile(
    id: id,
    name: name,
    archetype: archetype,
    skill: skill,
    strategicBaseline: StrategicBaseline(
      vpipTarget: vpip,
      pfrTarget: pfr,
      threeBetFrequency: threeBet,
      // Below a pro's 1.0 even at max skill, so amateurs never play pure GTO.
      gtoAdherenceWeight: (0.5 + 0.5 * skill).clamp(0.0, 0.98),
    ),
    behavioralModifiers: BehavioralModifiers(
      tiltResistance: tiltResistance,
      exploitativeWeight: exploitativeWeight,
      riskPremiumCoefficient: riskPremium,
      // Amateurs don't systematically track opponents (Phase 3 wiring aside).
      weightOnOpponentHistory: 0.0,
    ),
  );
}

// --- The roster ------------------------------------------------------------
// Ratings and styles are the owner's assessment of his home game.

/// Experienced, straightforward; overvalues suited connectors preflop, sticky
/// with pairs, limps frequently, semibluffs draws.
final PlayerProfile daveMiller = buildAmateur(
  id: 'H001',
  name: 'Dave Miller',
  strength: 5,
  vpip: 0.30,
  pfr: 0.13, // wide VPIP≫PFR gap → limps a lot
  threeBet: 0.03,
  exploitativeWeight: 0.35,
  tiltResistance: 0.60,
);

/// Very experienced, mostly tight-aggressive; strong positional play and pot
/// odds, low bluff frequency, limps only behind multiple limpers.
final PlayerProfile dougNiemec = buildAmateur(
  id: 'H002',
  name: 'Doug Niemec',
  strength: 6,
  vpip: 0.23,
  pfr: 0.18, // tight, raises rather than limps
  threeBet: 0.05,
  exploitativeWeight: 0.15, // low bluff frequency
  tiltResistance: 0.80,
);

/// Experienced, straightforward; calls in position with many hands multiway,
/// never bluffs air, only occasionally pushes a semibluff hard.
final PlayerProfile jasonDouglas = buildAmateur(
  id: 'H003',
  name: 'Jason Douglas',
  strength: 6,
  vpip: 0.34, // loose caller
  pfr: 0.14, // calls > raises → passive
  threeBet: 0.02,
  exploitativeWeight: 0.15, // never bluffs with air
  tiltResistance: 0.60,
);

/// Thinking player; reads textures/position/stacks, wider (suited-heavy) range,
/// capable of big folds but also hero-calls suspected bluffers, plays draws.
final PlayerProfile mattRosen = buildAmateur(
  id: 'H004',
  name: 'Matt Rosen',
  strength: 6,
  vpip: 0.29,
  pfr: 0.19, // thinking TAG — disciplined, not spewy
  threeBet: 0.05,
  exploitativeWeight: 0.35, // plays draws / selective hero-calls, but folds well
  tiltResistance: 0.75,
);

/// Calling station; level-0, can't fold top/two pair to aggression, poor
/// positional awareness, fond of min-raising when he feels ahead, limps a lot.
final PlayerProfile frankDouglas = buildAmateur(
  id: 'H005',
  name: 'Frank Douglas',
  strength: 3,
  vpip: 0.50, // very loose
  pfr: 0.08, // limps a lot
  threeBet: 0.01,
  exploitativeWeight: 0.10, // doesn't bluff
  riskPremium: 0.80, // min-raises / small sizing
  tiltResistance: 0.35,
);

/// Loose-aggressive, experienced; bluffs when he senses weakness, limps
/// regularly, ignores position preflop, river-bluffs scare cards. Tricky.
final PlayerProfile mitch = buildAmateur(
  id: 'H006',
  name: 'Mitch',
  strength: 5,
  vpip: 0.40,
  pfr: 0.22,
  threeBet: 0.06,
  exploitativeWeight: 0.65, // frequent bluffs incl. rivers
  riskPremium: 1.15,
  tiltResistance: 0.55,
);

/// Erratic, mostly loose; c-bets too much, bluffs draws regularly, sticky with
/// pairs on scary boards, limps a lot.
final PlayerProfile patWray = buildAmateur(
  id: 'H007',
  name: 'Pat Wray',
  strength: 3,
  vpip: 0.44,
  pfr: 0.14, // limps a lot
  threeBet: 0.02,
  exploitativeWeight: 0.55, // over-c-bets / bluffs draws
  riskPremium: 1.10,
  tiltResistance: 0.35,
);

/// Tight-aggressive thinking player — the strongest amateur. Good opening
/// ranges and sizing, understands pot odds, capable of big folds, limps rarely.
final PlayerProfile philDiPinto = buildAmateur(
  id: 'H008',
  name: 'Phil DiPinto',
  strength: 8,
  vpip: 0.24, // solid, near-standard
  pfr: 0.19,
  threeBet: 0.06,
  exploitativeWeight: 0.35,
  tiltResistance: 0.85,
);

/// Loose-aggressive; bluffs when the board fits and he reads weakness, limps a
/// lot, calls down too wide.
final PlayerProfile robGustine = buildAmateur(
  id: 'H009',
  name: 'Rob Gustine',
  strength: 4,
  vpip: 0.42,
  pfr: 0.18, // limps a lot
  threeBet: 0.04,
  exploitativeWeight: 0.55,
  riskPremium: 1.10,
  tiltResistance: 0.45,
);

/// Balanced; understands position and pot odds, river-bluffs missed draws,
/// folds two pair to aggression when obvious draws complete.
final PlayerProfile ramseyYeheah = buildAmateur(
  id: 'H010',
  name: 'Ramsey Yeheah',
  strength: 5,
  vpip: 0.27,
  pfr: 0.18,
  threeBet: 0.05,
  exploitativeWeight: 0.40,
  tiltResistance: 0.70,
);

/// Loose-aggressive, tricky; likes the 3-bet squeeze, plays draws hard, wide
/// opening range, three-barrels passive opponents, but folds rivers when pushed.
final PlayerProfile justinVidovitch = buildAmateur(
  id: 'H011',
  name: 'Justin Vidovitch',
  strength: 7,
  vpip: 0.34, // wide opener
  pfr: 0.26,
  threeBet: 0.09, // squeeze-happy
  exploitativeWeight: 0.70, // three-barrels
  riskPremium: 1.25, // goes for max value
  tiltResistance: 0.65,
);

/// Loose-aggressive positional player; loves the button, bluffs missed draws,
/// plays draws aggressively, hard to read, likes to limp.
final PlayerProfile haiLe = buildAmateur(
  id: 'H012',
  name: 'Hai Le',
  strength: 5,
  vpip: 0.38,
  pfr: 0.20, // limps → gap
  threeBet: 0.06,
  exploitativeWeight: 0.60,
  riskPremium: 1.15,
  tiltResistance: 0.60,
);

/// Tight-aggressive, a little "old-man coffee"; limps occasionally behind
/// limpers, small value bets for crying calls, doesn't bluff much, semibluffs
/// draws but gives up when he misses.
final PlayerProfile johnPineta = buildAmateur(
  id: 'H013',
  name: 'John Pineta',
  strength: 6,
  vpip: 0.21, // a touch tight (OMC)
  pfr: 0.16,
  threeBet: 0.04,
  exploitativeWeight: 0.20, // doesn't bluff a lot
  riskPremium: 0.90, // small value sizing
  tiltResistance: 0.75,
);
