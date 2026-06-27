# Monte — Flutter client

A complete client-only Texas Hold'em game: you against heuristic bots, with the
full hand played out on-device. Built with **MVVM + Clean Architecture**
(feature-first, Riverpod) so that moving to a Ktor backend later requires no UI
changes.

## Run

```bash
flutter pub get
flutter run -d macos     # or -d chrome
flutter analyze
flutter test
```

## Architecture

MVVM + Clean Architecture, organized **feature-first**. Each layer has a clear job:
**presentation** (Views + ViewModels), **domain** (entities + interfaces, pure
Dart), **data** (repository impls + sources). Domain and data have no Flutter or
Riverpod imports.

```
lib/
├── core/                         shared across features
│   ├── di/
│   │   └── game_providers.dart   composition root: gameRepositoryProvider
│   │                             (swap LocalGameRepository -> RemoteGameRepository here)
│   ├── domain/
│   │   ├── engine/               pure-Dart Hold'em engine (no Flutter imports)
│   │   │   ├── card.dart            Rank / Suit / Card
│   │   │   ├── deck.dart            shuffle + deal (Fisher–Yates)
│   │   │   ├── hand_evaluator.dart  best 5-of-7, total ordering with tiebreakers
│   │   │   ├── player.dart          per-player chip/bet/fold state
│   │   │   ├── actions.dart         GameAction (fold/check/call/bet/raise/all-in)
│   │   │   ├── game.dart            PokerGame state machine: blinds, streets,
│   │   │   │                        betting-round completion, side pots
│   │   │   └── bot.dart             heuristic opponent
│   │   └── hand_history.dart     hand-history entity (JSON-serializable)
│   ├── presentation/
│   │   └── money_format.dart     MoneyScope: $ vs Big-Blind display
│   └── theme/app_theme.dart
└── features/
    ├── table/
    │   ├── domain/               GameRepository interface, TableSnapshot
    │   ├── data/                 LocalGameRepository (engine + bots),
    │   │                         RemoteGameRepository (stub for Ktor WS)
    │   └── presentation/         TableViewModel + TableScreen, widgets/
    ├── settings/
    │   ├── domain/               GameSettings, SettingsRepository interface
    │   ├── data/                 SharedPrefsSettingsRepository
    │   └── presentation/         SettingsController + SettingsScreen
    └── analytics/
        ├── domain/               PokerAnalytics (VPIP/PFR/AF/bb-per-100)
        └── presentation/         AnalyticsViewModel + AnalyticsScreen
```

### The `GameRepository` seam

Views talk only to ViewModels (Riverpod `Notifier`s); ViewModels talk only to
`GameRepository`. The repository exposes a `Stream<TableSnapshot>` plus commands
(`newGame()`, `startNextHand()`, `submitAction(...)`, `simulate(...)`). Nothing in
the UI knows whether the game runs locally or on a server.

- **Today:** `LocalGameRepository` owns a `PokerGame` and `BotStrategy`, applies the
  human's actions, auto-plays bots with a short delay, and records hand history.
- **Later:** implement `RemoteGameRepository` against the backend's `/ws/game`
  protocol and change one line in `core/di/game_providers.dart`. The engine in
  `core/domain/engine/` doubles as the reference for server-side validation.

### State & DI (Riverpod)

`game_providers.dart` is the composition root. `gameRepositoryProvider` binds the
`GameRepository` implementation (and rebuilds when player count / all-bots change).
ViewModels (`TableViewModel`, `SettingsController`, `AnalyticsViewModel`) hold
immutable state; Views `watch` them. Tests override providers via
`ProviderContainer` with fakes.

## Tests

Unit + integration, all green. Highlights:

- `test/hand_evaluator_test.dart` — categories, wheel straights, kickers, best-5-of-7, strict ranking.
- `test/game_test.dart` — chip conservation across randomized seeded hands, no negative stacks, button rotation.
- `test/analytics_test.dart` / `test/simulation_test.dart` — analytics math and all-bots simulation.
- `test/table/table_view_model_test.dart`, `test/settings/*`, `test/analytics/analytics_view_model_test.dart` — ViewModels/controllers via `ProviderContainer` overrides.
- `test/table_layout_test.dart` — heads-up and full-table layout without overflow.
- `test/widget_test.dart` — the app boots and renders the table.

## Tuning the game

Edit `TableConfig` in `lib/features/table/data/local_game_repository.dart` to change
opponent names/count, starting stacks, blinds, or bot "think" time. Player count,
display units ($/BB), and all-bots mode are also exposed in the in-app Settings
screen (persisted via `shared_preferences`).
