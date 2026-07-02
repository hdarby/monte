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
  - `trusts_reads`: `true | false` (gates read-based mechanics like `Soul_Read`)
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

### Profile A: The Small-Ball Hand Reader

**Target Dynamics:** Manages risk with wide preflop range by using smaller bet sizes.
Trusts hand reading ability and will sniff out bluffs to make hero calls.

**Custom Mechanic:** `Soul_Read`. Uncanny ability to significantly narrow range of
opponent's holdings based on understanding opponent tendencies, and to shift
gears to aggressive when the read warrants it.

```json
{
  "id": "P047",
  "name": "Daniel Negreanu",
  "archetype": "Small_Ball_Hand_Reader",
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
    "weight_on_opponent_history": 0.90
  },
  "engine_triggers": {
    "custom_mechanic": "Soul_Read",
    "trigger_condition": {
      "in_position": true,
      "min_street": "FLOP"
    },
    "action_modifier": {
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

## 3. Candidate Parameter Extensions (backlog)

A catalog of common behavioral modifiers used to define poker personalities.
These are **candidates, not commitments** — we may or may not implement them. They
extend the schema in Section 1; until one is implemented, treat it as documentation
of intent. Units follow the **Conventions** above: frequencies/weights/adherence
are `[0, 1]` fractions, multipliers are centred on `1.0` (unclamped), and a few
fields are integers (hand counts).

> Where a candidate overlaps existing work, it's cross-referenced: postflop
> frequencies relate to Appendix F; opponent-memory fields to Phase 3; sizing and
> overbet fields to the `Geometric_Overbet_Execution` mechanic (Phase 4);
> tilt fields extend `tilt_resistance` (Phase 3); bubble/ICM relates to the MTT
> trajectory in the project vision.

### 3.1 Expanded preflop nuances

Fine-tune baseline strategy before any community cards are dealt — the difference
between a flat, mechanical opening range and a dynamic one. These sit alongside
`strategic_baseline`'s `vpip_target` / `pfr_target` / `three_bet_frequency`.

- **`four_bet_frequency`** *(0–1)* — probability of re-raising a 3-bet. Separates
  tight-passive bots from aggressive meta-attackers.
- **`cold_call_frequency`** *(0–1)* — inclination to flat-call a raise when closing
  the action is not guaranteed (e.g. from the HJ or CO).
- **`limp_frequency`** *(0–1)* — tendency to enter a pot passively without raising.
  High for recreational archetypes; near-zero for elite bots.
- **`squeeze_frequency`** *(0–1)* — propensity to raise big over an open-raiser and
  one or more callers, typically from the blinds or late position.
- **`fold_to_three_bet_weight`** *(0–1)* — how easily the player surrenders their
  opening range to a 3-bet.

### 3.2 Advanced postflop tendencies & sizing modifiers

How the bot navigates flop/turn/river textures. These are the baseline postflop
frequencies flagged as a future extension in **Appendix F**.

- **`cbet_frequency_flop`** / **`cbet_frequency_turn`** *(0–1)* —
  continuation-betting thresholds as the preflop aggressor.
- **`fold_to_cbet_flop`** / **`fold_to_cbet_turn`** *(0–1)* — how sticky or elastic
  the player is when facing aggression on wet vs. dry textures.
- **`check_raise_frequency`** *(0–1)* — propensity to check-raise as the
  out-of-position defender (a strong tell for aggressive, exploitative profiles).
- **`river_bluff_frequency`** *(0–1)* — baseline for firing absolute air when missed
  draws complete on the final street.
- **`preferred_sizing_profiles`** *(object)* — default sizing bands per street/spot,
  replacing a single static multiplier. (Relates to
  `action_modifier.bet_size_multiplier_flop_turn_river` and the
  `Geometric_Overbet_Execution` mechanic.)
- **`flop_mdf_adherence`** *(0–1)* — adherence to Minimum Defense Frequency.
- **`overbet_threshold_river`** *(0–1, pot fraction cap)* — maximum pot-percentage
  the player is willing to jam/shove on the river.

### 3.3 Table dynamics & environmental awareness (the meta)

Adjust decisions based on variables independent of the two hole cards.

- **`stack_size_sensitivity`** *(multiplier, centred 1.0)* — modifies behavior by
  effective stack size (e.g. shifts toward a premium/survival mode under ~30BB,
  scales up creative aggression when 200BB deep).
- **`bubble_factor_coefficient`** *(multiplier, centred 1.0)* — scales the risk
  premium up as tournament payout thresholds approach. Crucial for ICM / MTT
  survival simulation (see the MTT trajectory in the project vision); composes with
  `risk_premium_coefficient`.
- **`position_awareness_slope`** *(0–1)* — how sharply the range opens up from UTG to
  the BTN. A flat slope plays the same cards from every seat; a steep slope is an
  elite positional strategist.
- **`multiway_aggression_decay`** *(multiplier, ≤ 1.0)* — shrinks betting/raising
  frequencies automatically when 3+ players are active in a pot.

### 3.4 Mental game & psychological states

Temporary, variable states that simulate human emotional flaws and deviation from a
pure math model. These extend the Phase 3 `tilt_resistance` work into a *stateful*
model.

- **`tilt_threshold`** *(BB)* — a breaking point: losing a pot larger than X big
  blinds over a short sample triggers a "Tilt State."
- **`tilt_behavior_modifiers`** *(object)* — dynamic shifts applied **only while
  tilted**:
  - **`vpip_inflation_multiplier`** *(multiplier, centred 1.0)* — e.g. `1.4×` normal
    VPIP as the player chases losses.
  - **`pfr_decay`** *(multiplier, ≤ 1.0)* — stops raising, starts passively calling
    down with weak holdings.
- **`patience_decay_rate`** *(0–1)* — simulates boredom: each consecutive preflop
  fold nudges the VPIP baseline up marginally until the player finally enters a pot,
  then resets.

### 3.5 Information processing & memory depth

How the bot builds opponent models over a long session. These are the substrate for
the Phase 3 `exploitative_weight` / `weight_on_opponent_history` composition
(Appendix B's `read_confidence`).

- **`sample_size_requirement`** *(int, hands)* — tracking hands required against an
  opponent before `exploitative_weight` unlocks and begins altering GTO play.
- **`memory_decay_halflife`** *(int, hands)* — older hands weigh less; actions 100
  hands ago count for less than the last 10 in the opponent profile.
- **`showdown_curiosity_coefficient`** *(0–1)* — propensity to call a final river bet
  with a marginal, losing hand purely to buy information.

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
- Seed the three pros (Negreanu, Addamo, Haxton) as built-in profiles.
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
  Negreanu 25.3 / 21.1 / 9.6 (tgt 26 / 21 / 9.5), Addamo 31.3 / 26.5 / 13.0 (tgt 32 /
  28 / 14). Validated by `test/ai/profile_calibration_test.dart`.

### Phase 2 — Skill via the search (`gto_adherence_weight`) — **IN PROGRESS**
- **Progressive bias (done):** `IsmctsConfig.biasWeight` pulls UCB selection
  toward the default policy's action, decaying as `bias/(1+visits)`. A shallow
  search now defaults to sound play instead of noisy over-exploration. Impact on
  MCTS@250 (6-max): median pot **417bb → 4bb**, stack-offs/hand **3.7 → 0.0**, vs
  heuristic **−18 → −0.4** (even). MCTS@1500 still +107. The MCTS brain is usable.
- **Skill via adherence (explored):** an earlier build ran profile seats as
  **calibrated frequencies preflop + MCTS postflop**, depth `150 + 400·gto_adherence`;
  same-style head-to-head, high-adherence beat low-adherence **+11.2 bb/100**. But
  that search used a *style-blind* (`BotStrategy`) rollout, so pros converged to one
  line postflop and expressed no personality. **Superseded** for default profile
  seating by the range-aware postflop brain below (Phase 3); the MCTS brain remains
  available via the `mcts` bot type.
- **Still open:** give the ISMCTS search a *range-aware, style-shaped* rollout
  without the MC-in-MC cost blowup, so search skill and personality can coexist for
  pros; tune the depth/latency curve; per-street iteration budgets.

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
- **Range-aware postflop (done):** `HandRange` (a perceived villain range built
  from the baked `preflopOf` table, tightened by raises/street) + `PostflopEquity`
  (Monte-Carlo runout equity via the real `HandEvaluator`, exact on the river) give
  policies an honest "how good is my hand vs what they can hold here" number that
  sees draws and kickers — replacing the old category-only postflop scalar.
- **Personality/GTO-vs-exploit postflop (done):** `PersonalityPolicy` (with
  `rangeAware`) decides on that equity — nits overfold, stations overcall, gamblers
  /maniacs hunt fold-equity and semibluff draws. `ProfilePostflopPolicy` expresses
  the profile dial: high `gto_adherence_weight` plays equity/pot-odds straight
  (Haxton anchor), while `exploit = (1 − gto_adherence)·exploitative_weight` applies
  pressure (thinner value, more bluffs/semibluff-raises) vs a static population
  prior. MCTS rollouts keep the cheap category estimate (no MC-in-MC).
- **Still open (per-opponent reads):** `exploitative_weight` +
  `weight_on_opponent_history` → wire the live `OpponentModel` (VPIP/PFR/AF +
  confidence) into these policies so the *perceived range* and exploit strength
  adapt per villain (the full Appendix B composition, incl. the confidence term).
- `risk_premium_coefficient` → bet-sizing / variance (extends today's CARA curve).
- `tilt_resistance` → stateful degradation after big losses.
- `overfold_to_river_action` → likelihood to exploitively fold to river bet from 
  recreational players due to the underbetting tendency of recreational players.

### Phase 3.5 — Skill dial & amateur (home-game) players — **DONE**
- **`skill` field** on `PlayerProfile` (`[0, 1]`, default **1.0**; JSON-optional so
  existing pros round-trip). 1.0 = flawless pro-tier execution; lower = weaker.
- **`AmateurPolicy`** (`amateur_policy.dart`) is the pro substrate degraded by
  `k = 1 − skill`: (a) Gaussian **read-noise** on the equity estimate (the primary,
  style-independent dial); (b) **misjudged perceived ranges** (nits imagine nits →
  overfold, stations imagine bluffers → call light); (c) a **pot-odds discipline**
  shift (loose call / tight overfold); (d) distorted value/bluff thresholds; (e) a
  bounded (≤10%) **plausible blunder**. Preflop leaks are a *widened analytic*
  `PreflopRanges` (loose calling, limps via the VPIP≫PFR gap, under-3-betting) — so
  amateurs bypass `ProfileCalibrator`. Every term is `k × (non-negative bias)`, so
  it's monotonic in skill and collapses onto the pro brain at `skill = 1`.
- **Home-game roster** (`home_game_profiles.dart`): `buildAmateur({strength 1–10,
  style knobs})` maps a strength rating to `skill` and stats; `homeGameProfiles`
  seeds two examples. Amateurs appear under a "Home game" group in the lineup
  editor and are seated via the same `_deciderForBot` seam.
- **Strength gate** (`test/ai/amateur_strength_test.dart`): a seeded, seat-rotated
  sim seats one amateur among the pro field. Observed: the strong-amateur example
  loses ~49 bb/100 to the pros (which each stay net-positive), the loose station
  ~199; and loss rate is monotonic in skill above the loss *floor* (very-low skills
  plateau near the max bleed a stack-topped game allows). This is the right
  instrument — a mixed table's bb/100 just measures who feasts on the biggest fish,
  and heads-up exposes the pros' 6-max ranges to blind-stealing.

### Phase 4 — Engine triggers (situational mechanics)
- Structured-condition evaluator + `action_modifier` application.
- Implement `Soul_Read` and `Geometric_Overbet_Execution`.

### Phase 5 — UI & integration
- Profile picker in the New Game / seat setup (named pros alongside archetypes).
- Analytics shows **target vs measured** per profile (a live calibration check).
- Persistence; retire the old 4-axis model once parity is reached.
