# Poker — Flutter client

A complete client-only Texas Hold'em game: you against three heuristic bots, with
the full hand played out on-device. Built so that moving to a Ktor backend later
requires no UI changes.

## Run

```bash
flutter pub get
flutter run -d macos     # or -d chrome
flutter analyze
flutter test
```

## Architecture

```
lib/
├── engine/        Pure Dart. No Flutter imports — portable & unit-testable.
│   ├── card.dart            Rank / Suit / Card
│   ├── deck.dart            shuffle + deal (Fisher–Yates)
│   ├── hand_evaluator.dart  best 5-of-7, total ordering with tiebreakers
│   ├── player.dart          per-player chip/bet/fold state
│   ├── actions.dart         GameAction (fold/check/call/bet/raise/all-in)
│   ├── game.dart            PokerGame state machine: blinds, streets,
│   │                        betting-round completion, side-pot resolution
│   └── bot.dart             heuristic opponent
│
├── data/          The seam between UI and "where the game lives".
│   ├── game_repository.dart        abstract interface (ChangeNotifier)
│   ├── local_game_repository.dart  client-only: drives engine + bots
│   ├── remote_game_repository.dart STUB for the future Ktor WebSocket client
│   └── table_snapshot.dart         immutable UI view (server-message shaped)
│
├── ui/
│   ├── screens/table_screen.dart   felt, seats, board, log, controls
│   └── widgets/                    cards, seats, board, action bar
│
├── theme/app_theme.dart
└── main.dart      builds LocalGameRepository — swap here for remote.
```

### The `GameRepository` seam

The UI only ever talks to `GameRepository`. It calls `newGame()`,
`startNextHand()`, `submitAction(...)`, and rebuilds from `snapshot`
(`TableSnapshot`). It has no idea whether the game runs locally or on a server.

- **Today:** `LocalGameRepository` owns a `PokerGame` and `BotStrategy`, applies
  the human's actions, and auto-plays bots with a short delay.
- **Later:** implement `RemoteGameRepository` against the backend's `/ws/game`
  protocol and change one line in `main.dart`. The engine in `lib/engine/`
  doubles as the reference for server-side validation.

## Tests

- `test/hand_evaluator_test.dart` — category detection, wheel straights, kickers,
  best-5-of-7 selection, strict ranking.
- `test/game_test.dart` — chip conservation across 200 randomized hands (seeded),
  no negative stacks, button rotation.
- `test/widget_test.dart` — the app boots and renders the table.

## Tuning the game

Edit `TableConfig` in `lib/data/local_game_repository.dart` to change opponent
names/count, starting stacks, blinds, or bot "think" time.
