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

  // ---- Streamed cash-game recreationals -----------------------------------
  _a('A004', 'Andy Stacks', 'Streamed_Cash_Rec',
      strength: 5, vpip: 0.42, pfr: 0.24, threeBet: 0.05,
      exploit: 0.6, risk: 1.3, tilt: 0.5,
      pos: 0.45, potOdds: 0.5, impliedOdds: 0.5,
      chars: const [
        PlayerCharacteristic(id: 'Tilt_Blowup', proficiency: 0.6),
        PlayerCharacteristic(id: 'Leverage_Pressure', proficiency: 0.5),
        PlayerCharacteristic(id: 'Float_And_Take_Away', proficiency: 0.4),
      ],
      desc: 'Aggressive streamed-cash amateur; fires until somebody stops him.'),

  // ---- Big-game recreationals ----------------------------------------------
  _a('A005', 'Andy Beal', 'Big_Game_Whale',
      strength: 7, vpip: 0.35, pfr: 0.26, threeBet: 0.08,
      exploit: 0.4, risk: 1.45, tilt: 0.7,
      pos: 0.6, potOdds: 0.85, impliedOdds: 0.6,
      chars: const [
        // Studied hard enough to frighten the Corporation, and his weapon was
        // stake size rather than post-flop finesse.
        PlayerCharacteristic(id: 'Leverage_Pressure', proficiency: 0.8),
        PlayerCharacteristic(id: 'Geometric_Overbet_Execution', proficiency: 0.6),
        PlayerCharacteristic(id: 'Tilt_Shutdown', proficiency: 0.3),
      ],
      desc: 'The banker who studied his way into the biggest game ever played.'),
  _a('A006', 'Guy Laliberte', 'Big_Game_Whale',
      strength: 5, vpip: 0.48, pfr: 0.22, threeBet: 0.05,
      exploit: 0.5, risk: 1.4, tilt: 0.65,
      pos: 0.4, potOdds: 0.45, impliedOdds: 0.5,
      chars: const [
        PlayerCharacteristic(id: 'Sticky_Showdown', proficiency: 0.7),
        PlayerCharacteristic(id: 'Tilt_Chase', proficiency: 0.5),
        PlayerCharacteristic(id: 'Leverage_Pressure', proficiency: 0.4),
      ],
      desc: 'The archetypal whale — enormous action, forgiving fundamentals.'),

  // ---- Main Event folk heroes ----------------------------------------------
  _a('A007', 'Darvin Moon', 'Folk_Hero_Amateur',
      strength: 4, vpip: 0.46, pfr: 0.16, threeBet: 0.02,
      exploit: 0.25, risk: 1.1, tilt: 0.75,
      pos: 0.25, potOdds: 0.35, impliedOdds: 0.35,
      chars: const [
        // The logger who reached heads-up by declining, more or less ever, to
        // fold. Sticky is not a flourish here, it is the entire game.
        PlayerCharacteristic(id: 'Sticky_Showdown', proficiency: 0.85),
        PlayerCharacteristic(id: 'Limp_Reraise', proficiency: 0.2),
      ],
      desc: 'Logger who ran to heads-up without ever finding the fold button.'),
  _a('A008', 'Dennis Phillips', 'Folk_Hero_Amateur',
      strength: 6, vpip: 0.24, pfr: 0.16, threeBet: 0.04,
      exploit: 0.3, risk: 0.95, tilt: 0.85,
      pos: 0.6, potOdds: 0.7, impliedOdds: 0.6,
      chars: const [
        PlayerCharacteristic(id: 'Underbluff_Exploit', proficiency: 0.5),
        PlayerCharacteristic(id: 'Slow_Play_Trap', proficiency: 0.4),
      ],
      desc: 'Sales manager who ran deep on patience and refused to spew.'),
  _a('A009', 'Steve Dannenmann', 'Folk_Hero_Amateur',
      strength: 5, vpip: 0.40, pfr: 0.20, threeBet: 0.04,
      exploit: 0.5, risk: 1.2, tilt: 0.6,
      pos: 0.4, potOdds: 0.45, impliedOdds: 0.5,
      chars: const [
        PlayerCharacteristic(id: 'Sticky_Showdown', proficiency: 0.6),
        PlayerCharacteristic(id: 'Tilt_Chase', proficiency: 0.4),
        PlayerCharacteristic(id: 'Float_And_Take_Away', proficiency: 0.3),
      ],
      desc: 'Accountant, cheerful gambler, runner-up who would call anyway.'),

  // ---- Vloggers -------------------------------------------------------------
  _a('A010', 'Tim Watts', 'Poker_Vlogger',
      strength: 5, vpip: 0.38, pfr: 0.15, threeBet: 0.03,
      exploit: 0.35, risk: 1.0, tilt: 0.7,
      pos: 0.4, potOdds: 0.5, impliedOdds: 0.55,
      chars: const [
        PlayerCharacteristic(id: 'Sticky_Showdown', proficiency: 0.55),
        PlayerCharacteristic(id: 'Limp_Reraise', proficiency: 0.3),
      ],
      desc: 'Trooper97 — old-school loose live player, happy to see a flop.'),
  _a('A011', 'Johnnie Vibes', 'Poker_Vlogger',
      strength: 6, vpip: 0.34, pfr: 0.22, threeBet: 0.06,
      exploit: 0.55, risk: 1.2, tilt: 0.6,
      pos: 0.6, potOdds: 0.65, impliedOdds: 0.6,
      chars: const [
        PlayerCharacteristic(id: 'Float_And_Take_Away', proficiency: 0.5),
        PlayerCharacteristic(id: 'Leverage_Pressure', proficiency: 0.5),
        PlayerCharacteristic(id: 'Tilt_Blowup', proficiency: 0.35),
      ],
      desc: 'Aggressive live-cash vlogger who likes taking pots away.'),

  // ---- Celebrities ----------------------------------------------------------
  // Rated from televised play and recorded results. Held to a lower confidence
  // than the tiers above on purpose: for most of these there is a reputation and
  // a handful of broadcast hands, not a body of hand histories.
  _a('A012', 'Shannon Elizabeth', 'Celebrity_Amateur',
      strength: 6, vpip: 0.27, pfr: 0.17, threeBet: 0.05,
      exploit: 0.35, risk: 1.0, tilt: 0.75,
      pos: 0.6, potOdds: 0.65, impliedOdds: 0.6,
      chars: const [
        PlayerCharacteristic(id: 'Soul_Read', proficiency: 0.4),
        PlayerCharacteristic(id: 'Underbluff_Exploit', proficiency: 0.4),
      ],
      desc: 'The most serious of the celebrity players; real cashes.'),
  _a('A013', 'Richard Seymour', 'Celebrity_Amateur',
      strength: 7, vpip: 0.26, pfr: 0.19, threeBet: 0.07,
      exploit: 0.45, risk: 1.15, tilt: 0.85,
      pos: 0.7, potOdds: 0.75, impliedOdds: 0.7,
      chars: const [
        PlayerCharacteristic(id: 'Leverage_Pressure', proficiency: 0.6),
        PlayerCharacteristic(id: 'Positional_Warfare', proficiency: 0.5),
        PlayerCharacteristic(id: 'Soul_Read', proficiency: 0.4),
      ],
      desc: 'Ex-NFL lineman turned near-professional; WSOP final tables.'),
  _a('A014', 'Jason Alexander', 'Celebrity_Amateur',
      strength: 5, vpip: 0.24, pfr: 0.14, threeBet: 0.03,
      exploit: 0.25, risk: 0.9, tilt: 0.7,
      pos: 0.5, potOdds: 0.6, impliedOdds: 0.5,
      chars: const [
        PlayerCharacteristic(id: 'Underbluff_Exploit', proficiency: 0.5),
        PlayerCharacteristic(id: 'Tilt_Shutdown', proficiency: 0.35),
      ],
      desc: 'Studious and cautious; folds rather than gambles.'),
  _a('A015', 'Hank Azaria', 'Celebrity_Amateur',
      strength: 5, vpip: 0.28, pfr: 0.16, threeBet: 0.04,
      exploit: 0.35, risk: 1.0, tilt: 0.7,
      pos: 0.5, potOdds: 0.55, impliedOdds: 0.55,
      chars: const [
        PlayerCharacteristic(id: 'Slow_Play_Trap', proficiency: 0.4),
      ],
      desc: 'Solid, unflashy celebrity regular.'),
  _a('A016', 'Don Cheadle', 'Celebrity_Amateur',
      strength: 5, vpip: 0.27, pfr: 0.16, threeBet: 0.04,
      exploit: 0.35, risk: 1.0, tilt: 0.75,
      pos: 0.5, potOdds: 0.55, impliedOdds: 0.5,
      chars: const [
        PlayerCharacteristic(id: 'Soul_Read', proficiency: 0.35),
        PlayerCharacteristic(id: 'Underbluff_Exploit', proficiency: 0.35),
      ],
      desc: 'Competent and composed, if unspectacular.'),
  _a('A017', 'Brad Garrett', 'Celebrity_Amateur',
      strength: 5, vpip: 0.38, pfr: 0.19, threeBet: 0.04,
      exploit: 0.5, risk: 1.2, tilt: 0.55,
      pos: 0.4, potOdds: 0.45, impliedOdds: 0.5,
      chars: const [
        PlayerCharacteristic(id: 'Sticky_Showdown', proficiency: 0.55),
        PlayerCharacteristic(id: 'Tilt_Blowup', proficiency: 0.45),
        PlayerCharacteristic(id: 'Float_And_Take_Away', proficiency: 0.35),
      ],
      desc: 'Loose, talkative and happy to gamble.'),
  _a('A018', 'Ray Romano', 'Celebrity_Amateur',
      strength: 4, vpip: 0.36, pfr: 0.13, threeBet: 0.02,
      exploit: 0.25, risk: 0.9, tilt: 0.7,
      pos: 0.3, potOdds: 0.4, impliedOdds: 0.4,
      chars: const [
        PlayerCharacteristic(id: 'Sticky_Showdown', proficiency: 0.6),
        PlayerCharacteristic(id: 'Limp_Reraise', proficiency: 0.25),
      ],
      desc: 'Enthusiastic, curious, and reliably too curious to fold.'),
  _a('A019', 'James Woods', 'Celebrity_Amateur',
      strength: 5, vpip: 0.34, pfr: 0.21, threeBet: 0.06,
      exploit: 0.6, risk: 1.25, tilt: 0.45,
      pos: 0.5, potOdds: 0.5, impliedOdds: 0.5,
      chars: const [
        PlayerCharacteristic(id: 'Tilt_Blowup', proficiency: 0.65),
        PlayerCharacteristic(id: 'Leverage_Pressure', proficiency: 0.5),
        PlayerCharacteristic(id: 'Float_And_Take_Away', proficiency: 0.4),
      ],
      desc: 'Aggressive and combustible in roughly equal measure.'),
  _a('A020', 'Aaron Paul', 'Celebrity_Amateur',
      strength: 4, vpip: 0.33, pfr: 0.14, threeBet: 0.02,
      exploit: 0.3, risk: 1.0, tilt: 0.65,
      pos: 0.35, potOdds: 0.4, impliedOdds: 0.45,
      chars: const [
        PlayerCharacteristic(id: 'Sticky_Showdown', proficiency: 0.5),
        PlayerCharacteristic(id: 'Tilt_Chase', proficiency: 0.35),
      ],
      desc: 'Casual player who came for the fun of it.'),
  _a('A021', 'Macaulay Culkin', 'Celebrity_Amateur',
      strength: 4, vpip: 0.35, pfr: 0.13, threeBet: 0.02,
      exploit: 0.3, risk: 0.95, tilt: 0.6,
      pos: 0.3, potOdds: 0.4, impliedOdds: 0.4,
      chars: const [
        PlayerCharacteristic(id: 'Sticky_Showdown', proficiency: 0.5),
        PlayerCharacteristic(id: 'Tilt_Chase', proficiency: 0.3),
      ],
      desc: 'Loose, casual, along for the ride.'),
  _a('A022', 'Boris Becker', 'Celebrity_Amateur',
      strength: 5, vpip: 0.30, pfr: 0.18, threeBet: 0.05,
      exploit: 0.45, risk: 1.1, tilt: 0.5,
      pos: 0.5, potOdds: 0.55, impliedOdds: 0.55,
      chars: const [
        PlayerCharacteristic(id: 'Tilt_Blowup', proficiency: 0.5),
        PlayerCharacteristic(id: 'Leverage_Pressure', proficiency: 0.4),
      ],
      desc: "A champion's competitiveness with an amateur's technique."),
  _a('A023', 'Michael Phelps', 'Celebrity_Amateur',
      strength: 5, vpip: 0.26, pfr: 0.17, threeBet: 0.05,
      exploit: 0.4, risk: 1.05, tilt: 0.8,
      pos: 0.5, potOdds: 0.6, impliedOdds: 0.5,
      chars: const [
        PlayerCharacteristic(id: 'Tilt_Shutdown', proficiency: 0.4),
        PlayerCharacteristic(id: 'Underbluff_Exploit', proficiency: 0.4),
      ],
      desc: "An athlete's discipline against a beginner's experience."),
  _a('A024', 'Paul Pierce', 'Celebrity_Amateur',
      strength: 4, vpip: 0.40, pfr: 0.18, threeBet: 0.04,
      exploit: 0.5, risk: 1.25, tilt: 0.5,
      pos: 0.35, potOdds: 0.4, impliedOdds: 0.45,
      chars: const [
        PlayerCharacteristic(id: 'Sticky_Showdown', proficiency: 0.6),
        PlayerCharacteristic(id: 'Tilt_Blowup', proficiency: 0.5),
        PlayerCharacteristic(id: 'Leverage_Pressure', proficiency: 0.4),
      ],
      desc: 'Competitive, loose, and allergic to being pushed off a pot.'),
  _a('A025', 'Neymar da Silva Santos Junior', 'Celebrity_Amateur',
      strength: 4, vpip: 0.45, pfr: 0.24, threeBet: 0.06,
      exploit: 0.6, risk: 1.4, tilt: 0.4,
      pos: 0.35, potOdds: 0.4, impliedOdds: 0.45,
      chars: const [
        PlayerCharacteristic(id: 'Tilt_Blowup', proficiency: 0.7),
        PlayerCharacteristic(id: 'Leverage_Pressure', proficiency: 0.6),
        PlayerCharacteristic(id: 'Sticky_Showdown', proficiency: 0.4),
      ],
      desc: 'Plays poker the way he plays football — fast, loose, theatrical.'),

  // ---- Moved out of the pro pack -------------------------------------------
  // All four are recreational in the sense that decides which brain runs: they
  // are businessmen and action players without a professional record, and the
  // pro policies are structurally incapable of the mistakes they actually make.
  _a('A026', 'Bill Perkins', 'Big_Game_Whale',
      strength: 7, vpip: 0.36, pfr: 0.24, threeBet: 0.07,
      exploit: 0.6, risk: 1.4, tilt: 0.6,
      pos: 0.6, potOdds: 0.7, impliedOdds: 0.6,
      chars: const [
        PlayerCharacteristic(id: 'Leverage_Pressure', proficiency: 0.7),
        PlayerCharacteristic(id: 'Geometric_Overbet_Execution', proficiency: 0.6),
        PlayerCharacteristic(id: 'Tilt_Chase', proficiency: 0.35),
      ],
      desc: 'Hedge-fund gambler who studies, and who loves a huge number.'),
  _a('A027', 'Eric Persson', 'Big_Game_Whale',
      strength: 6, vpip: 0.44, pfr: 0.30, threeBet: 0.09,
      exploit: 0.75, risk: 1.5, tilt: 0.4,
      pos: 0.5, potOdds: 0.5, impliedOdds: 0.5,
      chars: const [
        PlayerCharacteristic(id: 'Leverage_Pressure', proficiency: 0.85),
        PlayerCharacteristic(id: 'Tilt_Blowup', proficiency: 0.7),
        PlayerCharacteristic(id: 'Float_And_Take_Away', proficiency: 0.5),
        PlayerCharacteristic(id: 'Sticky_Showdown', proficiency: 0.4),
      ],
      desc: 'Casino owner who plays every pot like a personal argument.'),
  _a('A028', 'Nik Airball', 'Big_Game_Whale',
      strength: 6, vpip: 0.42, pfr: 0.31, threeBet: 0.09,
      exploit: 0.75, risk: 1.5, tilt: 0.5,
      pos: 0.55, potOdds: 0.55, impliedOdds: 0.5,
      chars: const [
        PlayerCharacteristic(id: 'Leverage_Pressure', proficiency: 0.85),
        PlayerCharacteristic(id: 'Geometric_Overbet_Execution', proficiency: 0.75),
        PlayerCharacteristic(id: 'Float_And_Take_Away', proficiency: 0.7),
        PlayerCharacteristic(id: 'Tilt_Blowup', proficiency: 0.6),
      ],
      desc: 'Provocative and hyper-aggressive; allergic to a small pot.'),
  _a('A029', 'Wesley Fei', 'Big_Game_Whale',
      strength: 5, vpip: 0.40, pfr: 0.28, threeBet: 0.07,
      exploit: 0.7, risk: 1.45, tilt: 0.55,
      pos: 0.45, potOdds: 0.45, impliedOdds: 0.5,
      chars: const [
        PlayerCharacteristic(id: 'Leverage_Pressure', proficiency: 0.8),
        PlayerCharacteristic(id: 'Sticky_Showdown', proficiency: 0.7),
        PlayerCharacteristic(id: 'Tilt_Chase', proficiency: 0.55),
      ],
      desc: 'Fearless big-bet gambler of the streamed-cash boom.'),

  // ---- The rest of the Mizrachi brothers -----------------------------------
  // Four of them play. Michael and Robert are in the pro pack on their records;
  // these two are a long way behind both, with results thin enough that rating
  // them as pros would mean inventing most of the profile. Recreational at the
  // top of the scale is the honest placement — and with feature tables now
  // live, several Mizrachis in one game is a moment the recap should catch.
  _a('A030', 'Eric Mizrachi', 'Family_Regular',
      strength: 7, vpip: 0.30, pfr: 0.20, threeBet: 0.06,
      exploit: 0.45, risk: 1.1, tilt: 0.65,
      pos: 0.6, potOdds: 0.7, impliedOdds: 0.65,
      chars: const [
        PlayerCharacteristic(id: 'Soul_Read', proficiency: 0.45),
        PlayerCharacteristic(id: 'Slow_Play_Trap', proficiency: 0.4),
      ],
      desc: 'Third of the Mizrachi brothers; competent, and in their shadow.'),
  _a('A031', 'Donny Mizrachi', 'Family_Regular',
      strength: 7, vpip: 0.29, pfr: 0.19, threeBet: 0.05,
      exploit: 0.40, risk: 1.05, tilt: 0.70,
      pos: 0.6, potOdds: 0.7, impliedOdds: 0.6,
      chars: const [
        PlayerCharacteristic(id: 'Slow_Play_Trap', proficiency: 0.45),
        PlayerCharacteristic(id: 'Underbluff_Exploit', proficiency: 0.4),
      ],
      desc: 'The fourth Mizrachi; steady, mixed-game raised, rarely bluffing.'),
];
