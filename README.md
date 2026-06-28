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
  stats*. Recreate real players' tendencies; three calibrated pros ship built-in.
- **Skill** — an **ISMCTS** search drives postflop play, depth scaled by a
  `gto_adherence` knob so disciplined pros *out-decide* weaker styles. A
  *progressive-bias* search defaults to sound play at low iteration counts and
  strengthens with more.

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
| Behavioral modifiers (exploit/opponent reads, risk, tilt) | 🟡 in progress (Phase 3) |
| Table UI (felt, seats, board, action bar, hand log) | ✅ done |
| Settings (2–10 players, $/BB toggle, all-bots), persisted | ✅ done |
| Hand-history recording + analytics (VPIP/PFR/AF) | ✅ done |
| Client-only single-player game | ✅ playable |
| MVVM + Clean Architecture (feature-first, Riverpod) | ✅ done |
| Ktor backend | 🟡 scaffold (routes/sockets/DB stubbed with TODOs) |
| Real-time multiplayer + persistence + MTTs | ⬜ TODO |

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
