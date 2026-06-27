# Poker

A No-Limit Texas Hold'em application.

- **`frontend/`** — Flutter / Dart client. **Active.** A complete, playable game runs
  entirely on-device (you vs. heuristic bots) in **client-only mode**.
- **`backend/`** — Kotlin / Ktor server. **Scaffold for later.** Compiles into a
  structured Ktor 3 app (WebSocket + Postgres/Exposed stubs) ready to host the
  real-time multiplayer game.

## Why this shape

The plan is to start client-only and move to client/server later without rewriting
the UI. The frontend is built around a single seam — the `GameRepository`
interface:

```
UI  ──►  GameRepository  ──►  LocalGameRepository   (today: on-device engine + bots)
                          └─►  RemoteGameRepository  (later: Ktor WebSocket client)
```

The same pure-Dart poker engine that runs the client today can be ported/validated
on the server, and the `TableSnapshot` the UI consumes is shaped like the messages
the server will broadcast. Swapping to the network is a one-line change in
`frontend/lib/main.dart`.

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
| Heuristic bots | ✅ done |
| Table UI (felt, seats, board, action bar, hand log) | ✅ done |
| Client-only single-player game | ✅ playable |
| Ktor backend | 🟡 scaffold (routes/sockets/DB stubbed with TODOs) |
| Real-time multiplayer + persistence | ⬜ TODO |

## Layout

```
poker/
├── frontend/                 Flutter app
│   ├── lib/
│   │   ├── engine/           pure-Dart Hold'em engine (no Flutter imports)
│   │   ├── data/             GameRepository seam + snapshots
│   │   ├── ui/               screens & widgets
│   │   └── theme/
│   └── test/                 evaluator + game-invariant + widget tests
└── backend/                  Ktor scaffold (see backend/README.md)
```
