# Monte — where everything lives

A map of the codebase, written so you can find things without grepping. For the
project's *intent* (vision, phased plan, working agreement) see
[CLAUDE.md](CLAUDE.md); this file is purely "what is where and why".

---

## The 30-second version

```
monte/
├── frontend/lib/
│   ├── main.dart          app entry + routing
│   ├── core/              things every feature may use
│   │   ├── domain/        the poker engine + the bot brains (pure Dart)
│   │   ├── presentation/  shared widgets & display formatting
│   │   ├── util/          pure formatting primitives
│   │   ├── theme/         colours
│   │   └── di/            composition root (the local↔remote swap seam)
│   └── features/          one folder per user-facing capability
│       ├── table/         playing a cash-game hand
│       ├── tournament/    playing an MTT
│       ├── coach/         in-hand advice
│       ├── eval_history/  permanent full-info tuning record
│       ├── history/       hand log
│       ├── reads/         persistent per-opponent stats
│       └── settings/      persisted game settings
└── backend/               Ktor scaffold (phase 2, mostly TODO)
```

**Three rules that explain most placement decisions:**

1. **Layers.** Every feature is `domain/` (pure logic) → `data/` (repositories,
   controllers, stores) → `presentation/` (ViewModels + Views). Dependencies
   point *inward*: presentation may import domain; domain imports nothing but
   other domain.
2. **`core/` is what more than one feature needs.** If only the tournament uses
   it, it goes in `features/tournament/`, not `core/`.
3. **Widgets don't hold logic.** A `Screen` lays out; a `ViewModel` decides; the
   `domain` computes. If a widget is doing arithmetic on chips, it's in the
   wrong place.

---

## `core/` — shared by everything

### `core/domain/engine/` — the rules of poker

Pure Dart, **no Flutter imports**, deliberately portable to Kotlin so the server
can reuse it as the rules authority in phase 2.

| File | What it is |
|---|---|
| `game.dart` | `PokerGame` — the state machine for one hand. Betting rounds, side pots, showdown. The single source of truth; even the bot search plays *this* forward rather than a second rulebook. |
| `card.dart`, `deck.dart` | Cards and the deck. `Deck.stacked` gives preset decks that survive reset/shuffle — the basis of every reproducible test. |
| `hand_evaluator.dart` | 5-from-7 best-hand evaluation → `HandValue` / `HandRank`. |
| `hand_strength.dart` | Two **different** preflop metrics, and the difference matters. `preflopOf` is heads-up all-in equity vs a random hand — right for push/fold and ICM shoves, and nothing else. `playabilityOf` adds suitedness, connectedness, pair value and a domination penalty, and is what every *hand-selection* path uses. Ranking selection by raw equity put K4o (top 45%) above 76s (top 68%) and filled opening ranges with disconnected offsuit junk. |
| `board_texture.dart` | Reads the board against the six textures — **dry, wet, monochrome, dynamic, static, paired** — plus suitedness, connectedness, live draws, and whether the board favours the raiser or the caller. Not mutually exclusive: a board is usually several at once. |
| `actions.dart` | `GameAction` / `ActionType` / `BettingRound`. |
| `bet_snap.dart` | Rounding bets to legal, human-looking chip denominations. |
| `bet_sizing.dart` | `potRaiseTo` / `potBetTo` / `snapRaiseTo` — the arithmetic turning a *decision about size* into a legal chip amount. Nothing here decides a size; it exists because this was six identical copy-pasted closures, which is why sizing used to be impossible to find. |
| `player.dart` | `Player` — a seat's stack, hole cards, in-hand state. |
| `decision_policy.dart` | **`DecisionPolicy`** — `decide(game, player) → GameAction`. The one interface every brain implements. |
| `bot.dart` | The simple heuristic bot (the default brain). |

### `core/domain/ai/` — the bot brains

This is the "Monte" in Monte Carlo. Also pure Dart.

**The search:**
- `ismcts.dart` — Information Set Monte Carlo Tree Search. UCB1 tree over hero
  decisions, opponents auto-played by a rollout policy, rewards normalised to
  ~[-1,1]. Seed-reproducible.
- `determinizer.dart` — samples a plausible hidden world (opponent holes +
  future board) per iteration. This is what makes the search work under
  imperfect information.
- `action_abstraction.dart` — discretises the move set (fold / check-call /
  pot-fraction bets / all-in) so the tree stays tractable.

**Personality & profiles:**
- `personality.dart` — the four tunable axes (`aggression`, `bluffFrequency`,
  `tightness`, `riskTolerance`) plus archetype presets.
- `personality_policy.dart` — fast threshold-shaping policy; doubles as the
  search's rollout self-model.
- `player_profile.dart` — a named personality (identity + skill + style).
- `famous_pros.dart`, `home_game_profiles.dart`, `player_profiles.dart`,
  `custom_players.dart` — the actual cast. Mostly **data**, which is why they're
  long files; there's no logic to extract.
- `profile_policy.dart` (preflop), `profile_postflop_policy.dart`,
  `profile_decider.dart`, `amateur_policy.dart` — how a profile turns into
  decisions. `ProfilePostflopPolicy.decide()` is now a thin shell: it computes
  the threshold-shifting inputs (read-derived exploit terms, personality, tilt)
  and hands them to `heuristic_postflop_evaluator.dart` /
  `personality_post_processor.dart` below — see that pair for the actual
  postflop judgement.
- `background_quality.dart` — `equityIterationScale(tableCount)`: scales
  Monte-Carlo equity iteration counts down for background-table seats in a
  big field (cheaper, still a real decision — not the fast heuristic this
  once was), ramping back to full resolution as the field consolidates
  toward the final tables. The live table's own opponents always get full
  resolution regardless of field size (see `TournamentController`'s
  `equityTableCountProvider`, separate from the search-cutover
  `tableCountProvider`).
- `decider_factory.dart` — **`buildDecider(BotType, profile, iterations)`**, the
  one factory. `BotType` lives here.
- `action_candidate.dart` — **`ActionCandidate`**: the small data contract
  (action, label, margin, a `meta` bag) the postflop evaluator and its
  post-processor pass between them.
- `heuristic_postflop_evaluator.dart` — **`HeuristicPostflopEvaluator`**: the
  postflop branch logic itself (value/bluff/check-raise-plan/slow-play-trap
  lines, sizing, the commitment gates `_commitOk`/`_flushCommitOk`) — moved out
  of `ProfilePostflopPolicy` so "what does this hand's math say" is separate
  from "how does personality distort it". It has no opinion on *why* a
  threshold moved; that's computed once by the caller and passed in as plain
  numbers. Returns the chosen `ActionCandidate` plus, at the two genuine
  two-live-candidate forks (call vs. fold near `callBar`; bet vs. check near
  the value/bluff threshold), a `runnerUp` for the post-processor to mix
  against — every other branch (float, trap, check-raise-plan, hero-call) is
  already probabilistic/commitment-gated with no well-defined alternative, so
  it leaves `runnerUp` null.
- `personality_post_processor.dart` — **`PersonalityPostProcessor`**: signature-
  move trigger bookkeeping (moved here from being scattered across every
  `ProfilePostflopPolicy` return point) plus `mix()`, a bounded logistic that
  treats a hand sitting within `closeDecisionMargin` (0.01) of its own
  threshold as the coin-flip it actually is, instead of a hard cutoff. Only
  perturbs genuine near-ties — nothing outside the margin is affected.

**Stack depth, SPR and position** — the shared readers. Each of these existed
as duplicated logic inside three separate policies before, and every copy
carried the same bug, so they live in one place now:
- `stack_context.dart` — **`StackContext`**: `depthBb` / `StackRegime`
  (pushFold → veryDeep) and `spr` / `SprBand` (committed → veryHigh). They are
  different quantities and both are needed: depth is a *preflop* concept, taken
  from start-of-hand stacks and constant through the hand; SPR is a *postflop*
  commitment concept that **falls** as the pot grows. Also does SPR-targeted bet
  sizing — pick the SPR you want to face when the money goes in, solve for the
  per-street bet.
- `open_sizing.dart` — **`OpenSizing`**: how *large* a first-in open-raise is,
  the preflop counterpart to `StackContext.fractionToReachSpr`. Derived from
  effective **stack depth** (deeper ⇒ larger, interpolated in log depth) and
  **dead money** (antes ⇒ *smaller*), plus a big blind per limper. Deliberately
  has **no cash/tournament flag**: the two formats differ because tournaments
  are shallow with antes and cash is deep without, so modelling the physics
  makes the format difference fall out. Note the ante term is the **opposite
  sign** to the one in `open_ranges.dart` — more dead money widens the *range*
  and shrinks the *size*.
- `open_ranges.dart` — **`OpenRanges`**: how much wider a seat opens an unopened
  pot, driven by players left to act *preflop* (not postflop order — the small
  blind is second-to-last preflop) and by dead money, so big-blind antes widen
  ranges. Normalised to average 1.0 across the table, which is what keeps each
  profile's calibrated VPIP/PFR on target.

**Signature moves** — the per-player character layer:
- `characteristic_catalog.dart` — the named moves a profile can carry, each with
  a 0–1 proficiency. Eleven now: the original four plus `Slow_Play_Trap`,
  `Sticky_Showdown`, `Float_And_Take_Away`, `Bubble_Predator`, `Limp_Reraise`,
  `Underbluff_Exploit`.
- `trigger_context.dart` — the shared predicate vocabulary moves are written
  against. Conditions are reusable; actions are code, because a line change is
  not a multiplier.
- `trigger_observer.dart` — counts firings so a move can be shown to do
  something. Non-negotiable: two earlier data models (`GeneralTraits`,
  `EngineTriggers`) are authored on every profile and read by nothing.

**Tilt** — the one stateful piece:
- `mental_state.dart` — `MentalState` (tilt pressure + a boredom counter),
  `MentalModel` (pure update rules), `MentalReads` (the seam, shaped like
  `OpponentReads`) and `MentalTable` (per-session tracking). Never persisted:
  nobody sits down still steaming about a pot from last week. `tilt_resistance`
  drives it, and the *shape* of the deviation is a characteristic —
  `Tilt_Blowup` / `Tilt_Chase` / `Tilt_Shutdown`.

**Reads & equity:**
- `player_stats.dart`, `player_read.dart`, `opponent_model.dart`,
  `opponent_reads.dart`, `opponent_range_read.dart` — what a bot has observed
  about an opponent, and what an opponent perceives about you.
- `hand_range.dart`, `preflop_ranges.dart`, `postflop_equity.dart`,
  `push_fold_chart.dart` — range and equity machinery, shared by bots and coach.
  `HandRange.polarisedOn` is the important one: it builds the range a villain
  would actually *bet* (value plus a bluff tail, middle removed) rather than
  their whole continuing range, which is what stops a bluff-catcher measuring
  huge equity against a pile of unpaired big cards and calling forever.
- `tournament_context.dart`, `icm_adjusted_decider.dart` — ICM pressure applied
  to a decision: short-stack push/fold, bubble/ladder folding discipline (both
  gated by `icmDiscipline`, off for amateurs — a skill gap), plus
  survival-pressure bet/raise size damping and a universal garbage-call trim
  (neither gated — even bad players feel "busting is permanent" some).
- `profile_calibrator.dart` — nudges a profile toward target stats.

### `core/domain/hand_history.dart`

`HandHistory` / `ActionRecord` — the **bot-facing** hand record. Folded and
mucked cards are masked. Opponent models and any display read only this.

> ⚠️ There are deliberately **two** hand records. The other is `EvalHand` (see
> `features/eval_history/`), which is full-information and must *never* reach a
> `DecisionPolicy` or `OpponentModel`. See CLAUDE.md for the full rule.

### `core/util/format.dart`

Pure-Dart formatting primitives — `formatChips`, `formatChipsWithBb`, `ordinal`,
`titleCase`, `abbreviateName`, `firstLastName`, `displayName`. Flutter-free on
purpose, so the domain (which narrates chip counts in recaps) can use them
without importing presentation.

*Not* the same job as `MoneyScope` — see below.

### `core/presentation/`

- `money_format.dart` — **`MoneyScope`** / `MoneyFormat`: the inherited widget
  deciding whether the table shows dollars or big blinds. All cross-cutting
  money display goes through this.
- `suit_color.dart` — suit → colour.
- `widgets/adaptive_player_name.dart` — a name that renders in full when it fits
  and abbreviates to "F. Last" when it doesn't.
- `bot_lineup_editor.dart` — the shared per-seat brain/style picker.

### `core/di/game_providers.dart`

The composition root. **This is the phase-2 swap seam**: `gameRepositoryProvider`
binds `GameRepository` to `LocalGameRepository` today; pointing it at
`RemoteGameRepository` is a one-line change.

---

## `features/` — one folder per capability

### `features/table/` — playing a hand

| Layer | File | Role |
|---|---|---|
| domain | `game_repository.dart` | **`GameRepository`** — the abstract interface the UI talks to. The only thing presentation knows about. |
| domain | `table_snapshot.dart` | `TableSnapshot` — flat, serializable table state. Shaped so a server could send exactly this. |
| domain | `table_config.dart` | `TableConfig` — seats, blinds, brains, callbacks. |
| data | `local_game_repository.dart` | On-device implementation: drives `PokerGame` + bots, records hands. Re-exports `TableConfig` for compatibility. |
| data | `remote_game_repository.dart` | Phase-2 WebSocket implementation (stub). |
| data | `table_snapshot_projection.dart` | `PokerGame` → `TableSnapshot`. |
| presentation | `table_view_model.dart` | The ViewModel. |
| presentation | `table_screen.dart` | The felt. Reused as-is by the tournament. |
| presentation | `widgets/` | Seats, board, action bar, dialogs. |

### `features/tournament/` — playing an MTT

The largest feature. Reuses `TableScreen` for the human's table and simulates
the rest.

**domain** (pure, testable, no Flutter):

| File | Role |
|---|---|
| `tournament_structure.dart` | Blind ladders + `LevelClockMode`. `withLevelMinutes(minutes)` overrides every level's length to a fixed real-minute duration and switches to `LevelClockMode.minutes` — the lobby's "Level length" setting, applied on top of whichever preset's blind ramp was picked; replaces the old baked-in hand-count-per-level. |
| `tournament_preset.dart` | The lobby's structure choices as an enum carrying its own label and structure. |
| `tournament_state.dart` | Live tournament state: players, tables, level. |
| `tournament_snapshot.dart` | Flat snapshot for the UI, incl. `StandingRow`, `SimProgress`, `ColorUpDisplay`, `clockElapsed`/`timeRemainingInLevel`. Stack-in-BB and vs-average maths live here as getters, not in widgets. |
| `field_builder.dart` | Composes the bot field from selections + auto-fill. Seedable and reproducible. `_recWeight` damps extremely loose recreational profiles (e.g. a 75%-VPIP "any two cards" caricature) so a big field doesn't over-sample them — steepened once already after they still turned up too often in practice. Pools sort by **last name** (`compareByLastName`, `core/util/format.dart`) at list-build time, not by hand-ordering the catalog files (a losing battle as more personalities get added). |
| `name_pool.dart` | ~2,400 lines of first/last names. Pure data — the reason this file is huge and the reason that's fine. |
| `payout_structure.dart`, `icm.dart` | Prize ladders (real pay jumps — tiers of tied places, not a distinct number per place) and ICM equity. |
| `seat_manager.dart` | Table balancing and seat moves. |
| `chip_set.dart` | Denominations and colour-ups. |
| `chronicle/` | See below. |
| `tournament_chronicle.dart` | **Barrel** re-exporting `chronicle/` — keeps older imports working. |

**`domain/chronicle/`** — turning real results into the between-levels recap:

- `hand_digest.dart` — `HandDigest` / `ShowdownEntry`: what the controller
  reports after each hand.
- `hand_replay.dart` — `HandReplay`, `ReplaySeat`, `ReplayStreet`,
  `ReplayAction`, `TablePosition`, `PlayerVerdict`: a full factual replay of one
  hand, with positions, stack depths, and every action's pot context.
- `hand_narrator.dart` — **Bart.** Turns a replay into commentary: a read on
  every street (texture, range narrowing, exact outs, pot odds, SPR, bluff
  justification) plus a closing take and a verdict on every player. Pure and
  deterministic — same hand in, same words out.
- `level_recap.dart` — `LevelRecap`, `NotablePot`, `ChipLeaderLine`: what the UI
  renders. `NotablePot.describe()` generates its own sentence, so *all* recap
  prose is domain-side and testable without Flutter.
- `player_meta.dart` — `PlayerMeta`: the running per-player counters every
  generator below reads/mutates. `L`-suffixed fields reset each level; the rest
  (`bestRankEver`, `wasCrippledEarlier`, `knockouts`) are tournament-wide.
- `chronicle_grammar.dart` — `ChronicleGrammar`: second-person agreement ("you
  are" vs "Alex is") so every generator can address the human without
  duplicating the he-said/you-said branch per template.
- `leaderboard_storylines.dart` — `LeaderboardStorylines`: swings that span the
  *whole tournament* — a former big name busting or fading levels after they
  last led, a genuine multi-level comeback from crippled. Kept apart from
  `tournament_chronicle.dart`'s own same-level storylines (a table bully, a
  within-level comeback), which only ever compare a level's start to its end.
- `tournament_chronicle.dart` — the orchestrator. Owns `beginLevel`/`record`/
  `buildRecap`, the single-level generators (intro, bubble, eliminations,
  risers, fallers, bounty, "your level"), and delegates grammar and cross-level
  storylines to the two modules above.

**data:**
- `tournament_controller.dart` — the orchestrator. Owns entrants, builds a fresh
  `PokerGame` per table per hand, records busts, rebalances tables, runs
  hand-for-hand on the bubble, and drives live play. Exposes three streams
  (`tableStream`, `tournamentStream`, `simProgressStream`).
  - **Background simulation is deliberately bounded to one round per human
    hand**, triggered from `_endHumanHand`, not an independent loop. A fully
    independent, continuously-running background loop was tried (so the
    field would keep moving in real time even while the player was slow to
    act) and caused catastrophic chip-conservation failures under stress — a
    120-runner field lost over 95% of its chips, and a smaller one crashed
    outright (`IntegerDivisionByZeroException`, an emptied table surviving
    into `_playHand`). One-round-per-human-hand is what keeps background
    hands playing at a pace near the player's own table (it can never get
    more than one hand ahead) *and* keeps rebalancing's bookkeeping correct.
    A separate lightweight `Timer` (`_startRealtimeTicker`) still advances
    the minutes-mode level clock and the away-pause check independently —
    it never touches `state.tables`/`state.players`, which is what makes it
    safe to run on its own schedule.
  - **`_humanHandActive`, not `_liveGame == null`, is the "is a hand in
    progress" signal** rebalancing must stay out of. `_liveGame` is only
    ever nulled once the human busts entirely (`_finishHeadless`) — between
    ordinary hands it just holds the *previous* hand's finished game, so
    guarding on it silently blocked rebalancing (and therefore table
    breaking) for the rest of the tournament after hand one. Already shipped
    once as a real bug.
  - **`_reconcileChipDrift()`** is a safety net, not a fix: after any
    narrow race in rebalancing loses or gains a few chips, it silently nudges
    a handful of random off-table (never the human's) seats to bring the
    total back to `entrants × startingStack`, in amounts far too small to
    notice. Called at every rebalance point and at both places a tournament
    can conclude (live and headless) — the finish check used to short-circuit
    before reconciliation got a chance to run, letting a drift on the very
    last hand survive into the final result.
  - **Pausing must stop the level clock too**, not just background
    simulation — `_startRealtimeTicker` pushes `_levelStartedAt` forward by
    its own tick interval while `_bgSimulator.isPaused`, since
    `_tickLevelRealtime` computes elapsed as `now - _levelStartedAt` fresh
    each call rather than accumulating; skipping the tick alone would have
    the next un-paused tick jump forward by the whole paused duration.
- `chronicle_recorder.dart` — translates finished engine hands into
  `HandDigest`/`HandReplay`. Split out because the controller *runs* the
  tournament and this *observes* it.
- `replay_builder.dart` — reconstructs a hand's positions, per-street action and
  pot sizes from the engine. Returns the replay **un-narrated**; the chronicle
  narrates only the level's biggest pot, since narration enumerates outs and
  would be wasted on every hand at every table.

**presentation:**
- `tournament_view_model.dart` — **owns the controller lifecycle** and projects
  its three streams into one immutable `TournamentUiState`. Widgets never touch
  the controller. Swapping to a remote controller is a change here only.
- `tournament_screen.dart` — layout + turning one-shot events into dialogs.
- `lobby_screen.dart` — collects the choices; delegates composition to
  `FieldBuilder`. Its app bar is also the one entry point to `career_screen.dart`
  — before this there was no way to see career stats without first finishing a
  tournament and tapping through the session review to its last page.
- `career_screen.dart` — career winnings for the player and every named
  personality, built from the same `CareerRow.from(...)` aggregation
  `SessionMarkdown`'s career table uses, so the two never disagree.
- `widgets/` — `tournament_hud.dart` (the stat bar), `hud_detail_dialogs.dart`
  (the popup behind each stat), `standings_panel.dart`, `recap_dialog.dart`,
  `feature_hand_view.dart`, `results_overlay.dart`, `color_up_dialog.dart`,
  `sim_pause_button.dart` (also `LevelClockBadge`, the ticking countdown next
  to the pause button), `detail_dialog.dart`, `lobby_widgets.dart`.

### `features/coach/` — in-hand advice

- `domain/coach_report.dart` — the value types: `ActionEv`, `RangeBreakdown`,
  `RangeCell`, `HandGrid`, `CoachReport`, `HandCoachInput`.
- `domain/hand_coach.dart` — `HandCoach.analyze()`. Reuses the same
  `PostflopEquity`/`HandRange` machinery the bots use, so its read matches how
  the table actually plays. Re-exports `coach_report.dart`.
- `presentation/coach_screen.dart`.

### `features/analytics/domain/analytics.dart` — a domain leftover, not a feature

The analytics **screen** (simulation controls, tuning UI) was removed — it had
stopped earning its keep. `PokerAnalytics`/`PlayerStats` (VPIP/PFR/AF/bb-100
from hand histories) survived the cut because it's load-bearing test
infrastructure (`test/analytics_test.dart`, `test/analytics/`,
`test/ai/amateur_strength_test.dart`, `profile_calibration_test.dart`, and
others compute stats through it), not because it's still a "feature." Per this
file's own rule 2 it belongs in `core/domain/` now that nothing under
`features/` uses it — left in place to avoid a many-file import churn nobody
asked for; move it there the next time it's touched for an unrelated reason.

### `features/eval_history/` — the tuning record

The **full-information** hand record (all hole cards, positions, model per
seat), captured at the same `_finalizeHand` seam via
`TableConfig.onEvalHandRecorded` and written only to an on-disk JSONL store.

- `domain/eval_hand.dart`, `domain/eval_metrics.dart`
- `domain/auto_tuner.dart`, `domain/profile_overrides.dart` — the offline tuner
  and its persisted output.
- `data/file_eval_history_store.dart`
- `presentation/eval_history_provider.dart`, `presentation/auto_tune_job.dart`

> Never route an `EvalHand` to a `DecisionPolicy` or `OpponentModel` — that
> leaks folded cards. Analytics → "Wipe tuning history" clears the file *and*
> in-session reads.

### Saving a tournament

- `tournament/domain/tournament_save.dart` — `TournamentSave`: the whole
  tournament as serialisable data (chips, seats, tables, level, prize pool,
  finish order, and the profile id at each seat). Taken **at a hand boundary**;
  the live hand and every bot's RNG position are deliberately not stored, so a
  load deals fresh from the saved chips.
- `tournament/data/tournament_save_store.dart` — one file per save, so a corrupt
  one costs that tournament rather than all of them. `TournamentController`
  gains `saveAs()` and a `restore()` factory.
- `tournament/presentation/widgets/saved_tournaments_dialog.dart` — the browser
  (select, then load / delete / delete all) plus the save-name prompt.

### `features/reads/`, `features/history/`, `features/settings/`

- `reads/data/player_stats_store.dart` — persistent per-opponent stats
  (`OpponentStatsService`, `PlayerStatsBook`).
- `history/` — the hand log screen + ViewModel.
- `settings/` — `GameSettings`, `PlayPace`, the repository interface, the
  SharedPreferences implementation, and `SettingsController`.

---

## Finding things

| I want to… | Go to |
|---|---|
| change the rules of poker | `core/domain/engine/game.dart` |
| change how a bot thinks | `core/domain/ai/` — `ismcts.dart` for search, `*_policy.dart` for style |
| give a player a signature move | `core/domain/ai/characteristic_catalog.dart` + the owning policy |
| add a condition a move can test | `core/domain/ai/trigger_context.dart` |
| change which hands a bot plays | `core/domain/engine/hand_strength.dart` (`playabilityOf`) |
| change opening ranges by seat, or ante/steal maths | `core/domain/ai/open_ranges.dart` |
| change **postflop** bet sizing, or deep-stack/SPR behaviour | `core/domain/ai/stack_context.dart` |
| change how big a **preflop open-raise** is | `core/domain/ai/open_sizing.dart` |
| change 3-bet / 4-bet sizing | the `raiseBy(...)` call sites in `core/domain/ai/profile_policy.dart` (still pot fractions) |
| change how a villain's range is read | `core/domain/ai/hand_range.dart` |
| change how players tilt | `core/domain/ai/mental_state.dart` |
| change the chip graphic or its hover legend | `core/presentation/widgets/chip_stack_view.dart`, `chip_legend.dart` |
| change tournament saving/loading | `features/tournament/domain/tournament_save.dart` |
| change which hand the recap narrates | `features/tournament/domain/chronicle/tournament_chronicle.dart` (`_featureScore`) |
| change tournament payouts | `features/tournament/domain/payout_structure.dart` |
| create or edit a player from the CLI | `tool/create_player.dart` |
| add or edit a personality | `core/domain/ai/famous_pros.dart` / `home_game_profiles.dart` |
| change what the felt looks like | `features/table/presentation/` |
| change the tournament HUD | `features/tournament/presentation/widgets/tournament_hud.dart` |
| change a HUD popup | `features/tournament/presentation/widgets/hud_detail_dialogs.dart` |
| change the standings list | `features/tournament/presentation/widgets/standings_panel.dart` |
| change recap wording | `features/tournament/domain/chronicle/tournament_chronicle.dart` |
| change what Bart says about a hand | `features/tournament/domain/chronicle/hand_narrator.dart` |
| change how a board is classified | `core/domain/engine/board_texture.dart` |
| change how the recap *looks* | `features/tournament/presentation/widgets/recap_dialog.dart` |
| change blind structures | `features/tournament/domain/tournament_structure.dart` (+ `tournament_preset.dart` to expose it) |
| change who's in the field | `features/tournament/domain/field_builder.dart` |
| add a lobby option | `features/tournament/presentation/lobby_screen.dart` |
| change career stats | `features/tournament/domain/tournament_result.dart` (`CareerRow`) + `features/tournament/presentation/career_screen.dart` |
| format a chip count | `core/util/format.dart` |
| switch $ vs BB display | `core/presentation/money_format.dart` |
| point the app at a server | `core/di/game_providers.dart` (one line) |

---

## Conventions

- **Domain is framework-free.** No `package:flutter` import below
  `features/*/domain/` or `core/domain/`. If you need a widget there, the logic
  is in the wrong layer.
- **Snapshots are flat and serializable.** `TableSnapshot` and
  `TournamentSnapshot` are shaped so a server could send them verbatim. Derived
  values (stack in BB, % of average) are **getters on the snapshot**, not
  computations in widgets.
- **Barrels for split types.** When a file grew too big to browse, its value
  types moved to a sibling file and the original re-exports them
  (`tournament_chronicle.dart`, `hand_coach.dart`, `local_game_repository.dart`).
  Existing imports keep working; new code should import the specific file.
- **Big files that are fine.** `name_pool.dart` (2.4k), `famous_pros.dart`,
  `home_game_profiles.dart` are pure data — size isn't a smell there.
- **Big files that got split.** `chronicle/tournament_chronicle.dart` grew past
  ~950 lines adding cross-level leaderboard storylines and the play-style
  breakdown; `player_meta.dart`, `chronicle_grammar.dart` and
  `leaderboard_storylines.dart` were pulled out (see above), landing the
  orchestrator back under 800. `tournament_controller.dart` (1.5k) is the next
  candidate — it hasn't been split yet, so treat any further growth there as a
  reason to look for a seam, not to keep appending.
- **Widget naming.** Public widgets live in `widgets/` and are named for what
  they show (`StandingsPanel`, `MetricBars`). Widgets private to one file keep
  the `_Underscore` prefix.

## Testing

`test/` mirrors `lib/`: `test/engine/`, `test/ai/`, `test/features/tournament/`,
`test/table/`, `test/coach/`, and so on.

```bash
cd frontend
flutter analyze          # must be zero issues
flutter test             # full suite
tool/test.sh new         # only recent-feature tests
tool/test.sh old|all|list
```

**Scope the run to what you changed.** The full suite is ~4 minutes, dominated
by simulation gates (`amateur_strength_test`, `profile_calibration_test`,
`deep_stack_discipline_test`, `postflop_discipline_test`). Recap/narrator edits
only need `test/features/tournament/hand_narrator_test.dart` and friends.
Reserve the full suite for shared domain code — engine, policies,
`StackContext`, `HandStrength` — where the blast radius is genuinely wide.

**The simulation gates are calibration, not unit tests.** They run hundreds of
hands and assert measured frequencies land in a band (fold-to-bet by bet size,
bust-outs per 100 hands, pot percentiles, VPIP/PFR vs target). When one fails,
work out whether the *behaviour* regressed or the band is now measuring the
wrong thing — a change in bet sizing legitimately moves fold-to-bet, because
fold-to-bet is only meaningful relative to the size being faced.
