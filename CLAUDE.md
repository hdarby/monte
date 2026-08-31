# Monte

**Monte** — a No-Limit Texas Hold'em training application. Monorepo: Flutter/Dart
client + Kotlin/Ktor backend. The name is **Monte Carlo**: the bots' intelligence
is built on an optimized **MCTS** (Monte Carlo Tree Search) engine, with tunable
personality and configurability layered on top.

> This file is built **iteratively**. Keep it lean and correct. When something here
> turns out to be wrong or stale, fix it in the same change. Don't speculatively
> expand sections — add detail when it's been decided and verified.

## Project Vision

A **play-money poker training app** — no real money, ever. North star: **the best
poker training app ever produced** (the detailed definition of "best" is TBD with
the owner; capture it here as it's decided).

**Trajectory:**
- **Now:** solo / on-device, for the owner's amusement and experimentation.
- **Later:** multiplayer **client/server**, including **scheduled multi-table
  tournaments (MTTs)**.

Everything below serves this. When in doubt, optimize for training value and for a
clean path to the client/server + MTT future.

## Phased plan

1. **Now — client-only.** The whole game runs on-device in the Flutter app.
2. **Later — client/server.** Kotlin **Ktor** backend over WebSockets, **Postgres**
   for persistence. Backend currently exists as a compiling scaffold (`backend/`)
   with routes/sockets/DB stubbed (TODOs).

## Architecture (the seam that makes phase 2 cheap)

- The UI talks only to the abstract `GameRepository` (`frontend/lib/data/`).
- Today: `LocalGameRepository` drives a pure-Dart engine + bots on-device.
- Later: `RemoteGameRepository` implements the same interface against the Ktor
  `/ws/game` protocol — swapping it is a one-line change in `frontend/lib/main.dart`.
- The pure-Dart engine (`frontend/lib/engine/`) has **no Flutter imports** and is
  meant to double as the reference for server-side rules validation. Backend
  `model/` DTOs mirror it to share a client/server contract.

### Target architecture & principles

- **MVVM + Clean Architecture.** Separate **presentation** (Views + ViewModels),
  **domain** (entities + use cases, framework-free), and **data** (repositories +
  sources). Views stay thin; logic lives in ViewModels / use cases; the domain has
  no Flutter or I/O dependencies.
- **Structure: feature-first.**
  ```
  lib/
    core/         shared domain (poker engine), shared presentation utils, DI
      di/         composition root: gameRepositoryProvider binds GameRepository
                  (swap LocalGameRepository -> RemoteGameRepository here)
    features/
      <feature>/
        domain/        entities, repository interfaces, use cases (pure Dart)
        data/          repository impls, data sources
        presentation/  ViewModels (Riverpod Notifiers) + Views (screens/widgets)
  ```
- **DI + state — frontend: Riverpod.** Providers (in `presentation`/`core/di`)
  supply repositories/use cases (DI) and hold ViewModel state. ViewModels are
  `Notifier`/`AsyncNotifier` exposing **immutable** state; Views `watch` them.
  **Domain and data stay framework-free** — plain Dart, constructor injection, no
  `ChangeNotifier`/Riverpod imports. Test via `ProviderContainer` overrides. (No
  codegen for now; can add `riverpod_generator` later.) Backend (phase 2) uses
  **Koin + Ktor** — the Kotlin analog for server-side DI.
- **Use cases: pragmatic.** Explicit use cases where there's real domain logic
  (simulate, analytics, evaluate); ViewModels may call repository interfaces
  directly for thin pass-throughs.
- The current `engine/`, `data/`, `ui/` split is a **stepping stone** — not yet
  full MVVM (widgets read `GameRepository` directly; no ViewModels/use cases yet).
  Evolve toward the target deliberately and verified; don't assume the code already
  conforms.

## Repo layout

> **See [ARCHITECTURE.md](ARCHITECTURE.md) for the full file-by-file map** —
> what lives where, why, and a "I want to change X → go to Y" index. The tree
> below is the summary.

```
monte/
├── frontend/   Flutter app (active)
│   └── lib/
│       ├── core/                    shared across features
│       │   ├── di/                  gameRepositoryProvider (composition root / swap seam)
│       │   ├── domain/engine/       pure-Dart Hold'em rules (deck, evaluator, betting, side pots,
│       │   │                        DecisionPolicy seam, HandStrength, heuristic bot)
│       │   ├── domain/ai/           bot intelligence: ISMCTS engine, determinizer, action
│       │   │                        abstraction, PersonalityProfile/policy, buildDecider factory
│       │   ├── domain/hand_history.dart   shared hand-history entity (bot-facing, masked)
│       │   ├── presentation/        MoneyScope ($ vs BB), suit colour + widgets/
│       │   ├── util/format.dart     pure formatting primitives (chips, ordinals, names)
│       │   └── theme/
│       └── features/
│           ├── table/{domain,data,presentation}      game + table UI (GameRepository,
│           │                                         TableConfig, TableViewModel)
│           ├── tournament/{domain,data,presentation} MTTs: structures, ICM, seating,
│           │                                         chronicle/ recaps, TournamentViewModel
│           ├── settings/{domain,data,presentation}   persisted GameSettings (SettingsController)
│           ├── analytics/{domain,presentation}       VPIP/PFR/AF (AnalyticsViewModel)
│           ├── coach/{domain,presentation}           in-hand coach: HandCoach (SPR/equity,
│           │                                          range beat/lose split, polarized reads,
│           │                                          per-action EV + recommendation) + screen
│           ├── history/presentation                  hand log screen + ViewModel
│           ├── reads/data                            persistent per-opponent stats
│           └── eval_history/{domain,data,presentation}  permanent full-info tuning
│                                                     record (EvalHand, JSONL store, EvalMetrics)
│                                                     + offline AutoTuner → persisted ProfileOverrides
└── backend/    Ktor scaffold (Postgres/Exposed, WebSocket — TODO)
```

> MVVM migration **complete**: settings, table, analytics and tournament all run
> on Riverpod Notifiers; Views are `Consumer`s that talk only to ViewModels.
> Domain and data are framework-free; the table repository exposes a
> `Stream<TableSnapshot>`. The remote/WebSocket swap is a one-line change in
> `core/di/game_providers.dart`.

## Bot intelligence (Monte Carlo)

The headline feature: bots driven by an **ISMCTS** (Information Set Monte Carlo
Tree Search) engine, the reason the app is named Monte. All in `core/domain/ai/`,
pure Dart (Kotlin-portable).

- **Imperfect info via determinization.** Each search iteration samples a
  plausible world (opponent holes + future board) the hero can't see
  (`determinizer.dart`) and plays it forward through the *real* `PokerGame`
  engine — single source of truth, no second rulebook. Needs `PokerGame.clone()`
  + `Deck` seeding (`Deck.stacked` decks are preset and survive reset/shuffle).
- **Search** (`ismcts.dart`): hero-decision UCB1 tree, opponents auto-played by a
  default policy; rewards = hero net chips normalized by total chips in play
  (~[-1,1]); returns the most-visited root action. Seed-reproducible. Move set is
  discretized by `action_abstraction.dart` (fold / check-call / pot-fraction
  bets / all-in).
- **Personality = tunable axes** (`personality.dart`): `aggression`,
  `bluffFrequency`, `tightness`, `riskTolerance` in [0,1], with archetype presets
  (tag/lag/nit/station/maniac). Expresses via `PersonalityPolicy` (fast, shapes
  thresholds; also the search's rollout self-model) and a CARA risk-utility
  transform on the MCTS payoff (strictly increasing → never inverts EV).
- **Seam:** `DecisionPolicy` (`decide(game, player) → GameAction`) unifies
  `BotStrategy` (heuristic), `PersonalityPolicy`, and `IsmctsEngine`.
  `buildDecider(BotType, profile, mctsIterations)` is the one factory; settings
  pick bot type + personality, threaded through `TableConfig`.
- **Verified strong:** a seeded duplicate-match gate has the MCTS bot beating the
  heuristic by ~43 bb/100. Default bot is `heuristic` (keeps eval mode + tests
  fast); MCTS/personality are opt-in via settings.
- **Known cost:** MCTS runs synchronously per decision, so `simulate()` with the
  MCTS brain is much slower than heuristic — fine for the live table, heavy for
  large batch runs.

### Poker judgement the profile bots apply

The named personalities (pros and recreationals) don't use the search — they run
`ProfilePolicy` preflop and `ProfilePostflopPolicy` after, and this is where most
play quality lives. Four shared concepts, each of which used to be duplicated
per-policy and drifted:

- **Postflop is split into base evaluation and personality post-processing.**
  `ProfilePostflopPolicy.decide()` used to be one ~700-line function
  interleaving the equity/threshold math with personality, tilt, opponent-read
  and signature-move logic inline at every return point. It now only computes
  the threshold-shifting inputs (read-derived exploit terms, personality, tilt)
  and hands them to `HeuristicPostflopEvaluator` (the branch logic — value/
  bluff/check-raise-plan/slow-play-trap lines, sizing, the commitment gates)
  and `PersonalityPostProcessor` (signature-move trigger bookkeeping, plus a
  new bounded close-decision mix). The contract between them is
  `ActionCandidate` (`action_candidate.dart`): the evaluator returns a chosen
  candidate and, at the two genuine two-live-candidate forks (call vs. fold
  near `callBar`; bet vs. check near the value/bluff threshold), a `runnerUp`.
  `PersonalityPostProcessor.mix()` treats a hand within `closeDecisionMargin`
  (0.01) of its own bar as the coin-flip it actually is — e.g. a call worth
  +12.4 chips vs. a fold worth +12.0 no longer always breaks the same way —
  instead of a hard cutoff. Every other signature-move branch is already
  probabilistic or commitment-gated with no well-defined alternative, so it's
  left as a documented non-comparative pass-through (`runnerUp: null`) rather
  than forced into a comparison that would misrepresent it. Preflop
  (`ProfilePolicy`) is untouched — it stays a percentile cutoff against
  `HandStrength.playability`/`OpenRanges`, not a candidate-scored decision.
  `closeDecisionMargin` had to be tuned down from an initially-reasonable 0.05:
  because `margin` is a single noisy Monte-Carlo equity sample (~160
  iterations), a 0.05 window let sampling noise alone make hands look "close"
  that weren't, measurably collapsing `Sticky_Showdown`'s fold rate and
  silencing `Float_And_Take_Away` — caught by `signature_moves_test`, not
  missed.
- **Two preflop metrics, and mixing them up is a real bug.**
  `HandStrength.preflopOf` is heads-up all-in equity vs a random hand — correct
  for push/fold and ICM shoves only. `HandStrength.playabilityOf` is for *hand
  selection* everywhere else. Ranking selection by raw equity puts K4o above 76s
  and fills opening ranges with disconnected offsuit junk that flops dominated
  top pairs. Recreational players deliberately blend *back* toward raw equity in
  proportion to `1 − skill` — "K4 is two big cards" is their actual leak, and it
  is part of why they stay net losers.
- **`StackContext` (`stack_context.dart`)** — the one reader for stack depth and
  SPR. Depth (`depthBb`, `StackRegime`) is a *preflop* concept taken from
  start-of-hand stacks and constant through the hand; SPR (`spr`, `SprBand`) is a
  *postflop* commitment concept that falls as the pot grows. Reading depth off
  the *remaining* stack is the bug to watch for: it makes deep-stack discipline
  fade out exactly as a pot bloats.
- **SPR-targeted sizing** — *postflop* bets are not a blind pot fraction. A hand
  picks the SPR it wants to face when the money goes in and solves for the
  per-street size. Targets are *proportional* to the current SPR, since an
  absolute target demands an enormous bet when deep, which is backwards.
- **`OpenSizing` (`open_sizing.dart`)** — the preflop counterpart, and it had no
  model at all until it got one: every preflop raise was `minRaiseTo + 0.5·pot`,
  which preflop is the **constant 2.75 BB** at every depth in every format. Open
  size now comes from stack depth (deeper ⇒ larger, interpolated in *log* depth)
  and dead money, plus a big blind per limper.
  - **The ante term has the opposite sign to the one in `OpenRanges`.** More
    dead money widens the *range* and shrinks the *size*. Getting this backwards
    is what made the bots open *bigger* in tournaments (3.25 BB) than in cash
    (2.75 BB), since the big-blind ante is the only large preflop pot lever.
  - **No cash/tournament flag, deliberately** — the formats differ because
    tournaments are shallow with antes and cash is deep without, so modelling
    the physics makes the difference fall out. The known hole was a *deep*
    tournament (300 BB, no ante — nothing here marks Main Event level 1 as a
    tournament) — closed by `IcmAdjustedDecider`'s survival-pressure damping
    below, not by shading these anchors further.
- **All sizing arithmetic is in `engine/bet_sizing.dart`** (`potRaiseTo` /
  `potBetTo` / `snapRaiseTo`). It was six identical copy-pasted closures across
  five policies, which is why bet sizing was so hard to find and change: the
  boring question buried the interesting one six times over.
- **Amateur first-in bet sizing is randomised, not fixed**
  (`AmateurPolicy._firstInSizeFraction`). It used to be exactly
  `0.55 × sizeScale` pot every single time a rec led into an empty pot —
  same number on every hand, which is why hands started feeling identical.
  Now it's a Gaussian spread around that same 0.55 baseline, ceiling raised
  ~50% (0.9 → 1.35 pot) for the occasional big one, plus a flop-only
  "pot-slam with a strong made hand" tendency gated on the profile's own
  risk appetite (`sizeScale > 1.1`) and only ~45% of the time even then — a
  trait some amateurs have and others genuinely don't, not universal.
- **3-bet sizing is position-aware** (`ProfilePolicy.threeBetVsOpener`, via
  `OpenRanges.actsAfterPostflop`): ~3x the open in position, ~4x out of it,
  since acting last for the rest of the hand is what lets a smaller 3-bet get
  away with it. The flat `0.6` pot fraction it replaced measured out to only
  ~2.57x regardless of seat — below even the in-position number. Deliberately
  *not* applied to `AmateurPolicy`: sizing the same 3-bet regardless of
  position is itself a believable recreational leak, not a gap to close.
- **`OpenRanges` (`open_ranges.dart`)** — open-raising frequency by seat and
  dead money, as **additive percentage points, not a multiplier**. Anchored to
  real 9/10-handed data: ~13% under the gun rising to ~42% on the button, which
  is six positions apart, so ~4.8 points a seat *in a straight line*. An
  exponential in players-behind gets the middle seats right and then compounds
  at the top (+2,+2,+3,+5,+5,+5 measured), overshooting exactly where ranges are
  widest and hardest to play.
  - The slope is scaled by **`position_awareness`** — another field authored on
    every profile and read by nothing until it got this job. That published
    curve belongs to a *fully* aware player; pros carry 0.9 and land 15→40,
    recreationals default to 0.5 and play visibly flatter. The population
    average falls out near 3 points a seat, which is what aggregate data shows.
  - Position is ranked by players left to act **preflop** — the small blind is
    second-to-last, not first; that is postflop order — and big-blind antes
    widen every seat, because a steal is playing for more.
  - The adjustment is **mean-zero across the table**, which is what keeps each
    profile's calibrated VPIP/PFR on target; anything that shifts the mean will
    break `profile_calibration_test`.
  - **PFR is not RFI.** PFR counts raises against every hand *dealt*; an
    open-raise only happens on the rarer occasions the pot is folded to you, and
    there you raise far more freely. Treating a 20% PFR as a 20% opening
    frequency put the whole curve a third too low.
  - Anchor the shift on the **calibrated** cut (`_ranges.pfr`), never the raw
    target. Deriving it from `pfrTarget` bypasses whatever `ProfileCalibrator`
    tuned, leaving the calibration loop unable to move opening frequency at all
    — that bug had Negreanu 3-betting 1.5% against a 9.5% target.
- **Check-raising** — measured at 0.6% of check-then-face-a-bet spots against a
  real 8–15%, and the cause was not a missing action. With a strong hand the
  policy always bet, so anybody facing a bet after checking necessarily held
  something weak. Players need a *reason to check strong*; the same shape of bug
  hid `Float_And_Take_Away` entirely. **If a two-part move never fires, look for
  the missing first half before touching the second.**
- **Buy-in dial** — `PlayerProfile.atStakes` tightens ranges while raising the
  pfr:vpip ratio (fewer hands, played harder), and `FieldBuilder` weights the pro
  pool by buy-in. A $10k field is both tougher players *and* better ones.

- **`sizeScale` (personality) now reaches preflop.** `ProfilePostflopPolicy`
  already scaled its bet-size fraction by `riskPremiumCoefficient.clamp(0.6,
  1.6)` — postflop, an aggressive player genuinely bet bigger. `ProfilePolicy`/
  `AmateurPolicy` now apply the same clamp to `OpenSizing` and the 3-bet
  fraction. Before this, every profile opened and 3-bet identically at a given
  depth: no signal to read, because there was no variance to produce one —
  which is exactly what made preflop sizing feel exploitable. `OpenSizing` also
  takes an optional `Random` for a small, zero-mean jitter, for the same reason
  postflop already jitters: a perfectly deterministic open size is a tell.
- **`IcmAdjustedDecider` survival-pressure size damping** closes `OpenSizing`'s
  known deep-tournament hole. `TournamentController._ladderPressure` is
  provably zero at 300 BB / level 1 of a large field (`zone` needs to be near
  the money bubble; `vulnerability` needs `stackInBb < 40`) — both conditions
  fail simultaneously at the exact spot the "tournaments bust too many players
  early" complaint was about, so the *entire* ICM layer used to be inert there.
  `_survivalPressure` adds a `0.18` baseline that fires on **every** tournament
  hand regardless of ladder/bubble state — "this bust is permanent" is true on
  hand one, not just near the money — then `_dampSize` shrinks a surviving
  bet/raise toward the legal minimum proportionally. Proportional, not
  absolute, so an aggressive player's bigger `sizeScale`-driven open still
  comes out bigger than a nit's after damping — personality survives, the
  whole table just plays smaller than the identical lineup would in cash.
  Never touches `ActionType.allIn` (a jam is a deliberate full commitment
  already gated by `stackOff`/`vs3betCall`) and is exactly 0 for
  `TournamentContext.cash` (`playersLeft <= 0`), which is what makes cash stay
  the "spicier" format without touching anything cash-specific.
- **`icmDiscipline` splits the ICM *math* from ICM *instinct*.** Push/fold
  charts, bubble/ladder folding, and `Bubble_Predator` are a skill — amateurs
  are deliberately excluded (`TournamentController` passes
  `icmDiscipline: !isAmateurProfile(profile)`), same as before. But "I probably
  shouldn't call raises with any two cards as often when busting is permanent"
  isn't ICM math, it's survival instinct, and even bad players have some —
  survival-pressure size damping and the new garbage-call trim
  (`_trimGarbageCall`: a small, capped *chance* to fold a genuinely weak call,
  scaled by the same baseline pressure) apply to **every** wrapped seat
  regardless of the flag. `TournamentController` now wraps every seat in
  `IcmAdjustedDecider` rather than excluding amateurs from it outright — this
  is what tempers amateur pot-bloat in tournaments without flattening them
  into nits (the trim only touches calls well below any defensible continue,
  and only probabilistically, so a station's character survives).

### Signature moves — where the *fidelity* lives

Shared logic makes everyone play better and, unavoidably, more alike. Each
profile is otherwise separated by only seven scalars, so per-player character
has to come from the **`PlayerCharacteristic` catalog**
(`characteristic_catalog.dart`): named, bespoke moves that say how *this* player
plays. That is the differentiator (see the project vision), so prefer adding a
characterful named move over another generic dial.

- **`trigger_context.dart`** — the shared predicate vocabulary a move is written
  against (`inPosition`, `checkedToMe`, `calledFlop`, `madeAtLeast`, `hasTopPair`,
  `sprBelow`, `villainIsRecreational`, …). The **conditions** are reusable data;
  the **actions are not**. "Check your monster and spring it later" is a
  different *line*, not a bigger bet, which is exactly why the spec's
  `action_modifier` multipliers could never express these — and why
  `EngineTriggers` has sat authored-but-unread on three profiles since day one.
- **`trigger_observer.dart`** — counts firings, by move and by player. Built
  *alongside* the moves, deliberately: `GeneralTraits` and `EngineTriggers` are
  both authored everywhere and read by nothing, and nobody noticed because there
  was no way to ask "did this ever do anything?". A move that cannot be shown to
  fire is dead weight. `signature_moves_test.dart` runs a real 600-hand session
  and fails if one stops firing.
- Record a firing only when the move **changed the decision**, not merely when
  its condition held — a counter that ticks on every hand tells you nothing.
- A move shifts *frequencies*; it must never bypass the commitment gates
  (`_commitOk`, the river floors). Sticky means one more crying call, not a
  300 BB stack-off. There is a test for exactly that.
- **Moves reach the commentary.** `TriggerLog` collects what fired (with the
  street), the controller drains it per hand into `ReplayBuilder`, and the
  narrator names the move on the street it happened. A trap only *reads* as a
  trap if somebody says so — otherwise the character authored into the profile
  is invisible. Every phrasing variant must name its own move; there's a test.
- **The recap picks the most *interesting* hand, not the biggest pot**
  (`TournamentChronicle._featureScore`). Only one hand per level is narrated, and
  on pot size alone signature moves essentially never got shown — measured over
  a 27-runner level, moves fired three times and none landed in the biggest pot.
  Pot stays the multiplicative base so a trivial hand can't win on flags alone.
  A hand the human *contested* **amplifies** the existing interest rather than
  adding to it: your own hands shouldn't automatically win the slot, only your
  good ones.

### Tilt — the stateful layer

`mental_state.dart` is the one piece of the model that **remembers**. Everything
else decides from the hand in front of it; tilt carries across hands.

- **`MentalState`** — `tiltPressure` (0–1, decays every hand) and
  `handsSinceVpip` (the boredom counter). Session-scoped and **never
  persisted**: nobody sits down still steaming about a pot from last week.
- **`MentalReads`** is a seam shaped exactly like `OpponentReads`, and for the
  same reason — the state has to outlive the policies, which are rebuilt
  whenever the lineup changes.
- **`tilt_resistance` is finally the field that decides who tilts.** Authored on
  all 184 profiles and read by nothing until now; it sets both how much pressure
  a beat adds and how fast it fades. No profile data needed editing.
- **The *shape* is a characteristic, not a dial.** `Tilt_Blowup` (wider *and*
  raising), `Tilt_Chase` (wider but passive — the extra hands call), and
  `Tilt_Shutdown` (tighter; the reaction nobody models, because tilt is assumed
  to mean aggression). A profile with no tilt style accumulates pressure and
  expresses none of it, so the pros who were never given one play exactly as
  before — there's a test for that.
- **Where each style can express itself differs.** First-in on the button it is
  raise or fold, so a chaser's widened *entry* range has nowhere to go; its
  character lives in the cold-call facing a raise, and postflop. Getting this
  wrong makes a chaser look like a blow-up.
- Tilt shifts *frequencies*; it never touches the commitment gates. A rattled
  player must lose money believably, not absurdly.
- **Evaluation runs do not accumulate it** (the `_evaluating` gate), or a
  profile's calibrated stats would drift as a simulation wears on.

> **Pushing the button wider still is not free.** Published charts put it near
> 40–45%; forcing that by hand cost the pro field real money — at a 1.22x button
> premium a recreational player went from −8 to +12…+20 bb/100 against a pro
> field. That is a fact about poker rather than a bug: a wide steal is only
> profitable when the players behind fold, and these pros fold *postflop*, so
> opening wider and giving up is how a station gets paid. Widening belongs where
> it is conditional on a read.

## Dev commands (run from `frontend/`)

```bash
flutter run -d macos      # or -d chrome
flutter analyze
flutter test               # full suite
tool/test.sh new           # only recent-feature tests
tool/test.sh old           # everything except the new tests
tool/test.sh all|list      # all / show which files each group resolves to
```

> `tool/test.sh` splits the suite into **new** (recent feature work, listed in
> the script's `NEW_TESTS`) and **old** (everything else). As features stabilise,
> move their files out of `NEW_TESTS`.

## Working agreement

- **Architecture:** follow MVVM + Clean Architecture (above). Keep the domain
  framework-free; views thin; logic in ViewModels / use cases.
- **Tests are continuous, but don't auto-run them.** Keep writing/editing
  **unit and integration** tests alongside every change (no skips, no empty
  assertions; cover engine rules, ViewModels/use cases, analytics). But running
  the suite costs tokens — **ask before running tests**, and prefer a targeted
  run (`tool/test.sh new`, or a single file) over the full suite.
- **Scope the run to what changed.** Recap/narrator edits need only the recap
  tests, not the ~4-minute suite. Reserve the full run for shared domain code
  (engine, policies, `StackContext`, `HandStrength`) where the blast radius is
  wide. `flutter analyze` always.
- **Some gates are calibration, not unit tests.** `postflop_discipline_test`,
  `deep_stack_discipline_test`, `profile_calibration_test` and
  `amateur_strength_test` simulate hundreds of hands and assert *measured
  frequencies* land in a band. When one fails, decide honestly whether the
  behaviour regressed or the band now measures the wrong thing — e.g.
  fold-to-bet is only meaningful relative to the bet size being faced, so a
  sizing change legitimately moves it.
- **TDD when it fits.** For well-specified logic (rules, evaluator, analytics,
  tournament structures) we often write the test first.
- **Verify, don't assume.** Iterate in small steps: change → `flutter analyze`
  (zero issues) → confirm behavior. Run tests when asked; keep them green.
- **Pre-commit hygiene (every commit).** Remove unused imports and dead code, lint
  the codebase, ensure analyze and tests pass. Commit only when asked.

## Gotchas

- Engine stays pure (no Flutter imports); cross-cutting display formatting goes
  through `MoneyScope`.
- Flutter 3.44 / Dart 3.12 — this SDK uses `dependOnInheritedWidgetOfExactType`.
- macOS terminal lacks Screen Recording / Accessibility perms: I can't screenshot
  or foreground the running app — owner Cmd-Tabs to it.
- `cd X && cmd` in one Bash call does not persist the working dir to later calls.
- **Two hand records, kept separate on purpose.** `HandHistory` (bot-facing) masks
  folded/mucked cards — the opponent model and any display read only this ("no free
  information"). `EvalHand` (`features/eval_history/`) is the *full-information*
  tuning record (all cards, positions, model per seat), captured at the same
  `_finalizeHand` seam via `TableConfig.onEvalHandRecorded` and written only to the
  on-disk JSONL store. Never route an `EvalHand` to a `DecisionPolicy`/`OpponentModel`.
- **Two separate wipes, and they clear different things.** Analytics → **Wipe
  tuning history** deletes the `EvalHand` JSONL and resets *in-session* reads.
  Settings → **Clear all opponent reads** deletes the persisted
  `opponent_stats.json` (`OpponentStatsService.wipe()`). Neither does the other's
  job. After changing decision logic, clear the reads — statistics gathered under
  the old behaviour describe a game that no longer exists, and an exploitative
  bot will keep acting on them.
- **Two preflop strength metrics.** `HandStrength.preflopOf` = all-in equity
  (push/fold and ICM only). `HandStrength.playabilityOf` = hand selection. Using
  the former to pick starting hands is a real bug that has already shipped once.
- **`String.hashCode` is not stable across processes.** Anything that must
  reproduce between runs — the narrator's phrasing seed, for one — has to hash
  content by hand (`_Voice.of` walks the characters). An in-process determinism
  test cannot catch this; it looks fine and drifts between sessions.
- **Antes are tournament-only.** `TableConfig` has no ante field; only the
  tournament path (`TournamentStructure` → `PokerGame(ante:)`) posts one. Driving
  the engine directly is the way to test ante behaviour.
- **Career stats ignore generated (anonymous field-filler) entrants
  entirely** (`TournamentFinish.generated`, checked in `CareerRow.from`). A
  big field reuses a small template pool for filler, so the same profileId
  can sit at hundreds of tables in one event — counting those inflated a
  template's "played" count into the hundreds after a single tournament.
  Only the personalities the owner actually picked get a career line.
- **Background tournament simulation is capped at one round per human
  hand, on purpose** — not a fully independent loop. An independent,
  continuously-running loop (so the field kept moving in real time even
  while the player was slow to act) caused catastrophic chip-conservation
  failures under stress (a 120-runner field lost over 95% of its chips; a
  smaller one crashed outright). One round per human hand is what keeps
  background hands near the player's own pace and keeps the bust/rebalance
  bookkeeping correct — don't decouple this again without a very good reason
  and a stress test to back it up.
- **`_humanHandActive`, not `_liveGame == null`, is "is a hand in
  progress."** `_liveGame` is only nulled once the human busts entirely;
  between ordinary hands it holds the *previous* hand's finished game.
  Guarding rebalancing on `_liveGame == null` silently blocked table
  breaking for the rest of the tournament after hand one — already shipped
  once.
- **Pausing must freeze the level clock, not just background tables.**
  `TournamentController._startRealtimeTicker` computes elapsed level time as
  `now - _levelStartedAt` fresh each call, so merely skipping a tick while
  paused isn't enough — the next un-paused tick would jump forward by the
  whole paused duration. It pushes `_levelStartedAt` forward by the tick
  interval instead, while `_bgSimulator.isPaused`.
