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
│       ├── analytics/     stats + simulation + tuning UI
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
| `hand_strength.dart` | Cheap heuristic strength, used where a full evaluation is too slow. |
| `board_texture.dart` | Reads the board against the six textures — **dry, wet, monochrome, dynamic, static, paired** — plus suitedness, connectedness, live draws, and whether the board favours the raiser or the caller. Not mutually exclusive: a board is usually several at once. |
| `actions.dart` | `GameAction` / `ActionType` / `BettingRound`. |
| `bet_snap.dart` | Rounding bets to legal chip denominations. |
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
- `profile_policy.dart`, `profile_postflop_policy.dart`, `profile_decider.dart`,
  `amateur_policy.dart` — how a profile turns into decisions.
- `decider_factory.dart` — **`buildDecider(BotType, profile, iterations)`**, the
  one factory. `BotType` lives here.

**Reads & equity:**
- `player_stats.dart`, `player_read.dart`, `opponent_model.dart`,
  `opponent_reads.dart`, `opponent_range_read.dart` — what a bot has observed
  about an opponent, and what an opponent perceives about you.
- `hand_range.dart`, `preflop_ranges.dart`, `postflop_equity.dart`,
  `push_fold_chart.dart` — range and equity machinery, shared by bots and coach.
- `tournament_context.dart`, `icm_adjusted_decider.dart` — ICM pressure applied
  to a decision.
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
| `tournament_structure.dart` | Blind ladders + `LevelClockMode`. |
| `tournament_preset.dart` | The lobby's structure choices as an enum carrying its own label and structure. |
| `tournament_state.dart` | Live tournament state: players, tables, level. |
| `tournament_snapshot.dart` | Flat snapshot for the UI, incl. `StandingRow`, `SimProgress`, `ColorUpDisplay`. Stack-in-BB and vs-average maths live here as getters, not in widgets. |
| `field_builder.dart` | Composes the bot field from selections + auto-fill. Seedable and reproducible. |
| `name_pool.dart` | ~2,400 lines of first/last names. Pure data — the reason this file is huge and the reason that's fine. |
| `payout_structure.dart`, `icm.dart` | Prize ladders and ICM equity. |
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
- `tournament_chronicle.dart` — the narrator. Accumulates per-level tallies and
  generates the prose. One long file, but one coherent job.

**data:**
- `tournament_controller.dart` — the orchestrator. Owns entrants, builds a fresh
  `PokerGame` per table per hand, records busts, rebalances tables, runs
  hand-for-hand on the bubble, and drives live play. Exposes three streams
  (`tableStream`, `tournamentStream`, `simProgressStream`).
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
  `FieldBuilder`.
- `widgets/` — `tournament_hud.dart` (the stat bar), `hud_detail_dialogs.dart`
  (the popup behind each stat), `standings_panel.dart`, `recap_dialog.dart`,
  `feature_hand_view.dart`, `results_overlay.dart`, `color_up_dialog.dart`,
  `sim_progress_bar.dart`, `detail_dialog.dart`, `lobby_widgets.dart`.

### `features/coach/` — in-hand advice

- `domain/coach_report.dart` — the value types: `ActionEv`, `RangeBreakdown`,
  `RangeCell`, `HandGrid`, `CoachReport`, `HandCoachInput`.
- `domain/hand_coach.dart` — `HandCoach.analyze()`. Reuses the same
  `PostflopEquity`/`HandRange` machinery the bots use, so its read matches how
  the table actually plays. Re-exports `coach_report.dart`.
- `presentation/coach_screen.dart`.

### `features/analytics/` — stats, simulation, tuning

- `domain/analytics.dart` — VPIP / PFR / AF / bb-100 from hand histories.
- `presentation/analytics_view_model.dart` — simulation control + derived state.
- `presentation/analytics_screen.dart` — layout only.
- `presentation/widgets/` — `simulation_controls.dart`, `metric_bars.dart`,
  `data_tables.dart`, `tuning_section.dart`.

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
  `home_game_profiles.dart` are pure data. `tournament_controller.dart` (846)
  and `chronicle/tournament_chronicle.dart` (612) are each one coherent job.
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

> Known pre-existing failure: `test/show_behavior_test.dart` fails on `main`
> (an `ensureVisible` ambiguity in the settings widget test), unrelated to the
> layering above.
