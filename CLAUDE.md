# Poker

No-Limit Texas Hold'em application. Monorepo: Flutter/Dart client + Kotlin/Ktor backend.

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
      di/         composition root (get_it registrations)
    features/
      <feature>/
        domain/        entities, repository interfaces, use cases (pure Dart)
        data/          repository impls, data sources
        presentation/  ViewModels + Views (screens/widgets)
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

```
poker/
├── frontend/   Flutter app (active)
│   └── lib/
│       ├── core/                    shared across features
│       │   ├── domain/engine/       pure-Dart Hold'em rules (deck, evaluator, betting, side pots)
│       │   ├── domain/hand_history.dart   shared hand-history entity
│       │   ├── presentation/        MoneyScope ($ vs BB) + shared widgets
│       │   └── theme/
│       └── features/
│           ├── table/{domain,data,presentation}      game + table UI (GameRepository, TableSnapshot)
│           ├── settings/{domain,data,presentation}   persisted GameSettings
│           └── analytics/{domain,presentation}       VPIP/PFR/AF over hand histories
└── backend/    Ktor scaffold (Postgres/Exposed, WebSocket — TODO)
```

> MVVM migration: **settings** and **table** done (Riverpod Notifiers; the table
> repository is framework-free and exposes a `Stream<TableSnapshot>`). **Analytics**
> still drives its repository directly (full AnalyticsViewModel + composition-root
> cleanup remain — Steps 4–5).

## Dev commands (run from `frontend/`)

```bash
flutter run -d macos      # or -d chrome
flutter analyze
flutter test
```

## Working agreement

- **Architecture:** follow MVVM + Clean Architecture (above). Keep the domain
  framework-free; views thin; logic in ViewModels / use cases.
- **Tests are continuous.** Write/edit/delete **unit and integration** tests
  alongside every change. Keep the suite green and honest — no skips, no empty
  assertions. Cover engine rules, ViewModels/use cases, and analytics.
- **TDD when it fits.** For well-specified logic (rules, evaluator, analytics,
  tournament structures) we often write the test first.
- **Verify, don't assume.** Iterate in small steps: change → `flutter analyze`
  (zero issues) → `flutter test` (all green) → confirm behavior.
- **Pre-commit hygiene (every commit).** Remove unused imports and dead code, lint
  the codebase, ensure analyze and tests pass. Commit only when asked.

## Gotchas

- Engine stays pure (no Flutter imports); cross-cutting display formatting goes
  through `MoneyScope`.
- Flutter 3.44 / Dart 3.12 — this SDK uses `dependOnInheritedWidgetOfExactType`.
- macOS terminal lacks Screen Recording / Accessibility perms: I can't screenshot
  or foreground the running app — owner Cmd-Tabs to it.
- `cd X && cmd` in one Bash call does not persist the working dir to later calls.
