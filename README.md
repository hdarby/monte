# Monte

A **play-money** No-Limit Texas Hold'em **training app** — no real money, ever.
North star: the best poker training app ever produced. Solo / on-device today,
heading toward multiplayer client/server with scheduled multi-table tournaments.

- **`frontend/`** — Flutter / Dart client. **Active.** A complete, playable game runs
  entirely on-device (you vs. calibrated personality/profile bots driven by a Monte
  Carlo search) in **client-only mode**. Built with MVVM + Clean Architecture
  (feature-first, Riverpod). See `frontend/README.md`.
- **`backend/`** — Kotlin / Ktor server. **Scaffold for later.** Compiles into a
  structured Ktor 3 app (WebSocket + Postgres/Exposed stubs) ready to host the
  real-time multiplayer game.

## Why this shape

Start client-only and move to client/server later without rewriting the UI. The
frontend is built around a single seam — the `GameRepository` interface:

```
ViewModels ──► GameRepository ──► LocalGameRepository   (today: on-device engine + bots)
                              └─►  RemoteGameRepository  (later: Ktor WebSocket client)
```

The same pure-Dart poker engine that runs the client today can be ported/validated
on the server, and the `TableSnapshot` the UI consumes is shaped like the messages
the server will broadcast. Swapping to the network is a one-line change in
`frontend/lib/core/di/game_providers.dart`.

## Bot intelligence (Monte Carlo)

The headline feature: opponents modelled as **style + skill**, not a difficulty
slider.

- **Style** — poker-native frequency targets (VPIP / PFR / 3-bet). A closed-loop
  calibrator turns them into real preflop ranges, so a profile actually *hits its
  stats*. 154 calibrated pros and 30 recreational players ship built-in, and
  `tool/create_player.dart` adds your own.
- **Skill** — two brains. An **ISMCTS** search (the "Monte" in Monte Carlo) with
  progressive bias, and a faster range-aware policy that the named personalities
  use. Both express the same `gto_adherence` dial, so disciplined pros
  *out-decide* weaker styles.
- **Poker judgement**, not just search — hands are picked by *playability*
  (suitedness, connectedness, domination) rather than raw all-in equity; bet
  sizing targets a stack-to-pot ratio instead of a blind pot fraction; opening
  ranges run from ~13% under the gun to ~42% on the button, scaled by how
  position-aware each player is, and widen further for the dead money a steal is
  playing for. Recreational players keep the leaks — including overvaluing raw
  high cards — which is why they stay net losers to the pro field.
- **Character, not just competence** — shared "correct poker" makes everyone
  better *and* more alike, so each personality also carries **signature moves**:
  slow-play traps, floats, check-raises, bubble attacks, limp-reraises, refusing
  to fold a made hand. And they **tilt** — after a beat one player sprays, the
  next gets sticky, a third clams up — with `tilt_resistance` deciding who is
  susceptible and the *shape* coming from the player. Bart names the moves as
  they happen.

Full design + phased roadmap: [`docs/personality-model.md`](docs/personality-model.md).
The **Analytics** screen simulates any number of hands (with progress) and reports
VPIP/PFR/AF/win-rate per bot, so you can verify which settings actually win.

## Quick start (client-only)

```bash
cd frontend
flutter pub get
flutter run -d macos     # or: flutter run -d chrome
```

Run the checks:

```bash
cd frontend
flutter analyze
flutter test
```

## Backend (when you're ready)

The backend is a scaffold — see `backend/README.md`. One manual step is required
before it runs: the Gradle wrapper jar must be generated (`gradle wrapper`), since
it can't be committed as a binary here.

## Status

| Area | State |
|------|-------|
| Hand engine (deck, betting, side pots, 5-of-7 evaluation) | ✅ done, unit-tested |
| Heuristic + personality bots (bet-level discipline, no spew) | ✅ done |
| ISMCTS search (progressive bias; strong, usable at low iters) | ✅ done |
| Player profiles: calibrated style + MCTS skill (`gto_adherence`) | ✅ done (Phase 0–2) |
| Behavioral modifiers (exploit / opponent reads / risk) | ✅ done (Phase 3) |
| Signature moves per personality, named in the commentary | ✅ done |
| Tilt: stateful, per-player, three distinct styles | ✅ done |
| Table UI (felt, seats, board, action bar, hand log) | ✅ done |
| Settings (2–10 players, $/BB toggle, all-bots), persisted | ✅ done |
| Hand-history recording + analytics (VPIP/PFR/AF) | ✅ done |
| Client-only single-player game | ✅ playable |
| MVVM + Clean Architecture (feature-first, Riverpod) | ✅ done |
| Multi-table tournaments (structures, ICM, seating, payouts) | ✅ done, client-side |
| Tournament recaps + per-hand analysis ("Bart") | ✅ done |
| Persistent opponent reads across sessions | ✅ done |
| Save / load a tournament in progress | ✅ done (at hand boundaries) |
| Ktor backend | 🟡 scaffold (routes/sockets/DB stubbed with TODOs) |
| Real-time multiplayer + server-side persistence | ⬜ TODO |

## Layout

```
monte/
├── frontend/                 Flutter app (active)
│   └── lib/
│       ├── core/             shared across features
│       │   ├── di/           gameRepositoryProvider (composition root / swap seam)
│       │   ├── domain/       pure-Dart Hold'em engine + hand-history entity
│       │   ├── presentation/ MoneyScope ($ vs BB) + shared widgets
│       │   └── theme/
│       └── features/
│           ├── table/{domain,data,presentation}      game + table UI
│           ├── settings/{domain,data,presentation}   persisted GameSettings
│           └── analytics/{domain,presentation}       VPIP/PFR/AF
└── backend/                  Ktor scaffold (see backend/README.md)
```
