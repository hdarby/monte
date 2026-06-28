# Poker Player Personality Simulation Engine: Specification Document

This document serves as the master specification for generating, parsing, and
executing automated poker player profiles within a simulation loop. The engine
balances Game Theory Optimal (GTO) baselines against historical, behavioral, and
situational deviations (Exploitative plays).

> Source: owner's prior design work. Sections 1–2 are the spec as authored. The
> appendix captures engine-mapping notes and open items raised during review —
> see the companion discussion before implementing.

---

## 1. Core Architecture Schema

Every simulated player profile must map to the following structural data
contract (represented here in a baseline JSON specification).

```json
{
  "id": "UNIQUE_STRING_ID",
  "name": "PLAYER_NAME",
  "archetype": "ARCHETYPE_LABEL",
  "strategic_baseline": {
    "vpip_target": 0.00,
    "pfr_target": 0.00,
    "three_bet_frequency": 0.00,
    "gto_adherence_weight": 0.00
  },
  "behavioral_modifiers": {
    "tilt_resistance": 0.00,
    "exploitative_weight": 0.00,
    "risk_premium_coefficient": 0.00,
    "weight_on_opponent_history": 0.00
  },
  "engine_triggers": {
    "custom_mechanic": "MECHANIC_ENUM_OR_NULL",
    "trigger_condition": {
      "in_position": true,
      "min_street": "FLOP"
    },
    "action_modifier": {
      "trapping_frequency_flop_turn": 1.00,
      "postflop_aggression_multiplier_ip": 1.00,
      "bet_size_multiplier_flop_turn_river": 1.00
    }
  }
}
```

### Conventions

- **Frequencies are 0–1 fractions.** `vpip_target`, `pfr_target`,
  `three_bet_frequency`, and all `*_weight` / `*_resistance` fields are in
  `[0, 1]`. The UI renders them as percentages (e.g. `0.24` → "24%").
- **Multipliers are centred on 1.0.** `risk_premium_coefficient` and every
  `action_modifier.*` value is a multiplier where `1.0` = neutral, `> 1.0`
  amplifies, `< 1.0` dampens. These are *not* clamped to `[0, 1]`.
- **`trigger_condition` is a structured object**, not a string. Each present key
  is a predicate; all present keys are ANDed; omitted keys mean "don't care". A
  `null` `engine_triggers` means no situational override. Recognised keys:
  - `in_position`: `true | false`
  - `min_street`: `"PREFLOP" | "FLOP" | "TURN" | "RIVER"` (matches that street or
    later)
  - `has_nut_advantage`: `true | false`
  - (extend this whitelist as new mechanics need new predicates)

### Parameter Glossary

- **`gto_adherence_weight`**: Threshold (0.0 to 1.0) determining how rigidly the
  bot sticks to unexploitable frequencies. A value of 1.0 completely ignores
  opponent tendencies.
- **`exploitative_weight`**: The inclination (0.0 to 1.0) to deviate from base
  equity matrices to attack perceived opponent imbalances.
- **`engine_triggers`**: Hardcoded situational conditional overrides that bypass
  baseline probability checks when specific board/positional states are met.

---

## 2. Master Archetype Catalog

Use these verified profiles to instantiate your testing matrix or seed active
game tables.

### Profile A: The High-Stakes Positional Trapper

**Target Dynamics:** Plays relatively standard, tight-aggressive preflop
configurations, but fundamentally shifts behavior post-flop when holding absolute
positional advantage (In Position).

**Custom Mechanic:** `Positional_Leverage_Trap`. When IP on the Flop or Turn,
check-calling frequencies scale exponentially with medium-strong holdings to
disguise hand strength, followed by massive aggression multipliers on subsequent
streets.

```json
{
  "id": "P047",
  "name": "Hai Le",
  "archetype": "Lag_Positional_Trapper",
  "strategic_baseline": {
    "vpip_target": 0.26,
    "pfr_target": 0.21,
    "three_bet_frequency": 0.095,
    "gto_adherence_weight": 0.65
  },
  "behavioral_modifiers": {
    "tilt_resistance": 0.85,
    "exploitative_weight": 0.75,
    "risk_premium_coefficient": 0.90,
    "weight_on_opponent_history": 0.80
  },
  "engine_triggers": {
    "custom_mechanic": "Positional_Leverage_Trap",
    "trigger_condition": {
      "in_position": true,
      "min_street": "FLOP"
    },
    "action_modifier": {
      "trapping_frequency_flop_turn": 1.50,
      "postflop_aggression_multiplier_ip": 1.30
    }
  }
}
```

### Profile B: The Geometric Overbet Maximizer

**Target Dynamics:** World-class aggressive profile characterized by extreme,
non-standard bet sizing designed to maximize pressure on inelastic calling
ranges.

**Custom Mechanic:** `Geometric_Overbet_Execution`. Completely alters traditional
bet-sizing limits on late streets. Scales sizing exponentially based on pot
multipliers rather than raw hand equity.

```json
{
  "id": "P041",
  "name": "Michael Addamo",
  "archetype": "Hyper_Aggressive_Elite",
  "strategic_baseline": {
    "vpip_target": 0.32,
    "pfr_target": 0.28,
    "three_bet_frequency": 0.14,
    "gto_adherence_weight": 0.80
  },
  "behavioral_modifiers": {
    "tilt_resistance": 0.99,
    "exploitative_weight": 0.60,
    "risk_premium_coefficient": 1.50,
    "weight_on_opponent_history": 0.50
  },
  "engine_triggers": {
    "custom_mechanic": "Geometric_Overbet_Execution",
    "trigger_condition": {
      "min_street": "TURN",
      "has_nut_advantage": true
    },
    "action_modifier": {
      "bet_size_multiplier_flop_turn_river": 2.50
    }
  }
}
```

### Profile C: The Pure GTO Anchor

**Target Dynamics:** Inelastic, unbluffable, completely unexploitable
mathematical baseline framework. Completely ignores opponent metadata.

```json
{
  "id": "P001",
  "name": "Isaac Haxton",
  "archetype": "GTO_Wizard",
  "strategic_baseline": {
    "vpip_target": 0.24,
    "pfr_target": 0.195,
    "three_bet_frequency": 0.08,
    "gto_adherence_weight": 1.00
  },
  "behavioral_modifiers": {
    "tilt_resistance": 1.00,
    "exploitative_weight": 0.00,
    "risk_premium_coefficient": 1.00,
    "weight_on_opponent_history": 0.00
  },
  "engine_triggers": null
}
```

---

## Appendix: Engine-mapping notes & open items

Review notes for grounding the spec in Monte's actual engine (pure-Dart rules +
ISMCTS). Nothing here changes the design intent; it flags what must be pinned
down or bridged before implementation.

### A. Normalize units and document per-field scales — RESOLVED
All frequencies and weights are **0–1 fractions** (UI renders %); multipliers
(`risk_premium_coefficient`, `action_modifier.*`) are **centred on 1.0** and not
clamped. See **Conventions** above; the profiles now use these units.

### B. Define how `gto_adherence_weight` and `exploitative_weight` compose
They overlap conceptually (both govern "deviate from GTO?"). Recommended rule:
`gto_adherence_weight` sets baseline rigidity; the *strength* of any exploit is
`(1 − gto_adherence_weight) · exploitative_weight · read_confidence`, where
`read_confidence` grows with `weight_on_opponent_history` and sample size. This
keeps the Haxton anchor (adherence 1.0 ⇒ zero exploit) consistent and avoids
contradictory states.

### C. "GTO" in this engine = the ISMCTS search
Monte has no equilibrium solver. The ISMCTS engine (EV-maximizing, depth set by
`mctsIterations`) is our practical stand-in for "optimal." So:
- `gto_adherence_weight` → how strongly we follow the search's recommended action
  (and how much we randomize/balance) vs. a style/exploit shortcut.
- **Skill emerges from search depth + hand-reading**: deeper search and
  range-weighted determinization = a stronger player. Pros = high adherence + deep
  search; recreationals = shallow/heuristic + style leaks.

### D. Realizing `vpip`/`pfr`/`3bet` targets (calibration)
Targets are *inputs*; the engine must *hit* them. Feasible because we already
measure these in Analytics. Approach: rank starting hands (existing
`HandStrength` + a preflop chart) and pick the entry/raise/3bet thresholds that
yield the target frequency at the given table size/position. Validate by
simulating a profile and confirming measured VPIP ≈ target.

### E. `trigger_condition` representation — RESOLVED
Using **structured condition objects** (see Conventions): present keys are ANDed
predicates, omitted keys mean "don't care", `null` triggers means no override. No
string DSL / expression parser.

### F. Postflop stat coverage (future extension)
`strategic_baseline` is preflop-centric (VPIP/PFR/3bet). For full realism, add
postflop frequencies later: c-bet / fold-to-c-bet (per street), barrel frequency,
aggression frequency, WTSD / W$SD. The `engine_triggers.action_modifier`
multipliers cover bespoke signatures but not baseline postflop frequencies.

### G. Multiple mechanics per profile (future extension)
`engine_triggers` allows one `custom_mechanic`. Real players show several
signatures — consider a list of triggers when the single-mechanic model starts to
pinch.

---

## Implementation Roadmap

Incremental milestones — each is independently buildable, testable, and leaves the
app green. The new model is built **alongside** the existing archetype axes; we
migrate the UI to it once Phase 1 proves out, then retire the old `PersonalityProfile`.

### Phase 0 — Data model & parsing *(no behavior change)*
- `PlayerProfile` Dart model mirroring the schema (`strategic_baseline`,
  `behavioral_modifiers`, structured `engine_triggers`), with JSON round-trip and
  range/scale validation.
- Seed the three pros (Hai Le, Addamo, Haxton) as built-in profiles.
- **Validates:** the contract parses and survives a round-trip. Pure data — nothing
  in the engine changes yet.

### Phase 1 — Preflop calibration: targets → measured stats — **VPIP DONE**
- Built: `PreflopRanges` (maps a target frequency to a strength cutoff by
  enumerating all 1326 combos) + `ProfilePolicy` (calibrated preflop, heuristic
  postflop), plus a `TableConfig.deciderBuilder` seam to evaluate arbitrary
  policies through the existing repository + analytics.
- **Result:** **VPIP calibrates tightly** (e.g. Haxton 23.1 vs 24.0, Addamo 32.7
  vs 32.0 — within ~1 pt). **PFR and 3-bet undercount** (Haxton PFR 14.5 / 3-bet
  4.0 vs targets 19.5 / 8.0).
- **Why:** VPIP is a clean per-hand threshold ("did I put money in?"). PFR/3-bet
  are *position-dependent* — a PFR-range hand that faces a raise but isn't a 3-bet
  flats instead, so it doesn't count as a raise. A static strength cutoff can't
  compensate for that; the open range must be widened by an amount that depends on
  how often you face a raise.

### Phase 1b — Closed-loop PFR/3-bet calibration — **DONE**
- `ProfileCalibrator` (pure engine, cached): seats the profile as a single hero
  against a **reference field of competent heuristic opponents** (the realistic
  environment its real-world stats reflect — calibrating vs clones of itself
  distorts the dynamics and balloons VPIP), then runs a damped proportional
  fixed-point on the admitted fractions (PFR = opens + 3-bets, so it targets open
  = PFR − 3-bet), keeping the bands nested (3-bet ⊆ open ⊆ VPIP).
- **Result (all within ~1.5 pts):** Haxton 23.8 / 19.1 / 7.4 (tgt 24 / 19.5 / 8),
  Hai Le 25.3 / 21.1 / 9.6 (tgt 26 / 21 / 9.5), Addamo 31.3 / 26.5 / 13.0 (tgt 32 /
  28 / 14). Validated by `test/ai/profile_calibration_test.dart`.

### Phase 2 — Skill via the search (`gto_adherence_weight`)
- Map adherence to "follow the ISMCTS action vs a style shortcut"; tie skill to
  search depth (`mctsIterations`).
- **Validates:** head-to-head sims show the higher-adherence / deeper-search profile
  (Haxton) out-winning a lower-adherence one — pros dominate by judgment.
- **Note from the bet-level fix:** now that the heuristic plays soundly (no
  all-in spew), MCTS needs ~1500 iterations to clearly beat it (+99 bb/100 HU);
  at 250 it loses. The app's default `mctsIterations` (250, for speed) makes the
  MCTS brain *weak* — Phase 2 must address the search-depth vs latency trade-off.

### Diagnosis aids & the MCTS-is-weak reality
- **Hand transcripts**: every interactive hand prints a readable transcript
  (`HHLOG` prefix) via `TableConfig.onHandRecorded` → `HandHistory.toReadable()`,
  for reading back actual played hands.
- **Preflop strength was over-rating pairs** (88 ≈ 0.98 → treated as a premium and
  stacked off). Fixed to a smooth ladder (22 ≈ 0.50 … AA ≈ 0.95). Profile ranges
  re-baked against the new curve.
- **MCTS action abstraction** now drops deep-stack overbet shoves
  (`allInMaxPotMultiple`, `allInMaxBB`) and caps raises per street
  (`maxRaisesPerRound`) — kills the 100bb open-shoves.
- **But MCTS @ 250 iterations is fundamentally broken** in 6-max: median pot
  ~417bb, ~3.7 stack-offs/hand (vs **balanced personality 19bb / 0.02**). A weak
  search just maxes out the available betting and gets it in by the river;
  abstraction guards can't fix that. **Treat the MCTS brain as unusable until
  Phase 2** — use Personality/Profile bots (now sane) meanwhile.

### Engine: bet-level awareness (preflop spew fix)
- `PokerGame.raiseCountThisRound` exposes how many times the pot's been raised
  this street. Both `BotStrategy` and `ProfilePolicy` now tighten as it climbs
  (3-bet a range, but only premiums 4-bet/stack off) — fixing catastrophic all-in
  raise-wars where two "3-bet range" hands (A9o, QJs, small pairs) shipped 100bb
  preflop. Aggressive profiles' PFR/3-bet now *undershoot* slightly at 6-max as a
  result, which is the honest trade (sound play over inflated-by-spew stats).

### Phase 3 — Behavioral modifiers
- `exploitative_weight` + `weight_on_opponent_history` → lightweight opponent
  modelling (track opponents' measured stats, shade actions to attack imbalances),
  composed per Appendix B.
- `risk_premium_coefficient` → bet-sizing / variance (extends today's CARA curve).
- `tilt_resistance` → stateful degradation after big losses.

### Phase 4 — Engine triggers (situational mechanics)
- Structured-condition evaluator + `action_modifier` application.
- Implement `Positional_Leverage_Trap` and `Geometric_Overbet_Execution`.

### Phase 5 — UI & integration
- Profile picker in the New Game / seat setup (named pros alongside archetypes).
- Analytics shows **target vs measured** per profile (a live calibration check).
- Persistence; retire the old 4-axis model once parity is reached.
