import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/player_profile.dart';

/// Well-known **recreational** players — the celebrities, streamed-cash regulars
/// and folk-hero deep runners who are not professionals but are real, public,
/// researchable people.
///
/// A separate list from [homeGameProfiles] on purpose: that one is the owner's
/// actual home game, and these are strangers. Both are recreational, so both are
/// spread into the same roster and both run [AmateurPolicy].
///
/// **Recreational is a brain, not a judgement.** `skill == 1.0` runs the pro
/// policies; anything below runs the amateur one, which models the leaks these
/// players genuinely have — overvaluing raw high cards, calling too wide,
/// sizing erratically. A strong amateur belongs here at strength 8–9, not in the
/// pro pack at skill 1.0, because the pro brain cannot make those mistakes.
PlayerProfile _a(
  String id,
  String name,
  String archetype, {
  required int strength,
  required double vpip,
  required double pfr,
  required double threeBet,
  double exploit = 0.3,
  double risk = 1.0,
  double tilt = 0.6,
  double pos = 0.5,
  double potOdds = 0.5,
  double impliedOdds = 0.5,
  List<PlayerCharacteristic> chars = const [],
  required String desc,
}) {
  final base = buildAmateur(
    id: id,
    name: name,
    strength: strength,
    vpip: vpip,
    pfr: pfr,
    threeBet: threeBet,
    exploitativeWeight: exploit,
    riskPremium: risk,
    tiltResistance: tilt,
    archetype: archetype,
    characteristics: chars,
  );
  return PlayerProfile(
    id: base.id,
    name: base.name,
    archetype: base.archetype,
    skill: base.skill,
    strategicBaseline: base.strategicBaseline,
    behavioralModifiers: base.behavioralModifiers,
    characteristics: chars,
    generalTraits: GeneralTraits(
      positionAwareness: pos,
      potOdds: potOdds,
      impliedOdds: impliedOdds,
    ),
    description: desc,
  );
}

/// The roster (spread into `homeGameProfiles`).
final List<PlayerProfile> famousAmateurs = [
  // ---- Streamed cash-game recreationals -----------------------------------
  _a('A001', 'Robbi Jade Lew', 'Streamed_Cash_Rec',
      strength: 6, vpip: 0.34, pfr: 0.20, threeBet: 0.06,
      exploit: 0.55, risk: 1.15, tilt: 0.7,
      pos: 0.55, potOdds: 0.6, impliedOdds: 0.55,
      chars: const [
        // The hand she is known for is a call, so the sticky showdown is the
        // move: she does not fold when she has decided she is good.
        PlayerCharacteristic(id: 'Sticky_Showdown', proficiency: 0.75),
        PlayerCharacteristic(id: 'Float_And_Take_Away', proficiency: 0.4),
        PlayerCharacteristic(id: 'Tilt_Chase', proficiency: 0.3),
      ],
      desc: 'Bold streamed-cash regular; will not be bluffed off a decision.'),
  _a('A002', 'Tiffany Michelle', 'Semi_Pro_Broadcaster',
      strength: 7, vpip: 0.28, pfr: 0.17, threeBet: 0.05,
      exploit: 0.40, risk: 1.0, tilt: 0.75,
      pos: 0.7, potOdds: 0.75, impliedOdds: 0.7,
      chars: const [
        PlayerCharacteristic(id: 'Soul_Read', proficiency: 0.5),
        PlayerCharacteristic(id: 'Sticky_Showdown', proficiency: 0.4),
        PlayerCharacteristic(id: 'Tilt_Chase', proficiency: 0.25),
      ],
      desc: 'Deepest woman in the 2008 Main Event; broadcaster and grinder.'),

  // ---- Celebrity amateurs --------------------------------------------------
  _a('A003', 'Matt Damon', 'Studious_Celebrity',
      strength: 7, vpip: 0.26, pfr: 0.16, threeBet: 0.04,
      exploit: 0.35, risk: 0.95, tilt: 0.85,
      pos: 0.65, potOdds: 0.75, impliedOdds: 0.65,
      chars: const [
        // Studied the game hard for Rounders and kept playing; the leak is
        // caution rather than spew, so he under-bluffs and traps.
        PlayerCharacteristic(id: 'Underbluff_Exploit', proficiency: 0.45),
        PlayerCharacteristic(id: 'Slow_Play_Trap', proficiency: 0.35),
        PlayerCharacteristic(id: 'Tilt_Shutdown', proficiency: 0.3),
      ],
      desc: 'Genuinely studious celebrity amateur; cautious rather than spewy.'),
];
