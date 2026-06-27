# Poker Backend (Ktor)

Greenfield **scaffold** for the Texas Hold'em server. It boots, serves a health
check, exposes placeholder REST table endpoints, and accepts WebSocket
connections that currently just echo. The real-time game engine and persistence
are **TODO** — this project is the "for later" server that the Flutter client
will eventually connect to over WebSockets, with Postgres for persistence.

## Status

| Area | State |
| --- | --- |
| Project structure / build | Done |
| HTTP plugins (JSON, CORS, logging, status pages) | Done |
| WebSockets transport | Wired; **echo only** |
| Shared model / DTO contract | Done |
| REST table endpoints | **Stubbed** (in-memory samples) |
| Database (Exposed + Hikari + Postgres) | Configured but **optional/guarded**; schema only |
| Real-time poker game logic | **TODO** (see `routes/GameSocket.kt`) |
| Auth | **TODO** |

## Prerequisites

- **JDK 17** (the Gradle/Kotlin toolchain targets 17).

## Important: completing the Gradle wrapper

The wrapper scripts (`gradlew`, `gradlew.bat`) and
`gradle/wrapper/gradle-wrapper.properties` are included, **but the binary
`gradle/wrapper/gradle-wrapper.jar` is intentionally NOT committed** (a binary
jar cannot be hand-authored). You must generate it once before `./gradlew` will
work.

If you already have a system Gradle installed:

```bash
cd backend
gradle wrapper --gradle-version 8.12
```

If you do **not** have Gradle installed, either:

- Install it (e.g. `brew install gradle` on macOS, or via SDKMAN:
  `sdk install gradle 8.12`) and then run the command above, **or**
- Open the `backend/` folder in IntelliJ IDEA, which will provision the wrapper
  jar automatically on import.

After that, `./gradlew` is self-contained and downloads Gradle 8.12 as needed.

## Running

```bash
cd backend
./gradlew run
```

The server starts on **http://localhost:8080**.

Smoke test:

```bash
curl http://localhost:8080/health
# -> {"status":"ok"}

curl http://localhost:8080/api/tables
# -> [ ...sample tables... ]
```

WebSocket endpoint (echo placeholder): `ws://localhost:8080/ws/game`. Send a
JSON `ClientMessage`, e.g.:

```json
{ "type": "join", "tableId": "demo-1", "displayName": "Alice" }
```

## Running with Postgres

Persistence is **disabled by default** so the server boots without a database.
To enable it, start Postgres and set `DB_ENABLED=true`.

Start a local Postgres in Docker:

```bash
docker run --name poker-postgres \
  -e POSTGRES_DB=poker \
  -e POSTGRES_USER=poker \
  -e POSTGRES_PASSWORD=poker \
  -p 5432:5432 \
  -d postgres:16
```

Then run the server with persistence on:

```bash
cd backend
DB_ENABLED=true ./gradlew run
```

On startup the app creates the `users`, `tables`, and `hands` tables via Exposed
`SchemaUtils` (to be replaced by a real migration tool later).

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `PORT` | `8080` | HTTP listen port |
| `DB_ENABLED` | `false` | Turn persistence on/off |
| `DB_JDBC_URL` | `jdbc:postgresql://localhost:5432/poker` | JDBC URL |
| `DB_USER` | `poker` | Postgres user |
| `DB_PASSWORD` | `poker` | Postgres password |
| `DB_MAX_POOL_SIZE` | `10` | HikariCP max pool size |

## Project layout

```
backend/
├── build.gradle.kts              # Gradle Kotlin DSL build (Ktor plugin, app)
├── settings.gradle.kts
├── gradle/libs.versions.toml     # Version catalog
├── gradle/wrapper/               # Wrapper props + scripts (jar must be generated)
└── src/main/
    ├── kotlin/com/pokerapp/
    │   ├── Application.kt         # main() + module wiring
    │   ├── plugins/              # Serialization, Sockets, HTTP(CORS), Monitoring,
    │   │                         #   Routing, Databases
    │   ├── routes/               # healthRoutes, tableRoutes, gameSocket
    │   ├── model/                # @Serializable DTOs = client/server contract
    │   │                         #   Card, Player, TableState, GameAction, enums,
    │   │                         #   socket messages
    │   └── db/                   # Exposed tables + DatabaseFactory (HikariCP)
    └── resources/
        ├── application.conf      # HOCON config (port, postgres)
        └── logback.xml
```

## The client/server contract

The `model/` package holds the `@Serializable` types shared in shape with the
Flutter client. The Flutter client must mirror these enum names and the sealed
class `"type"` discriminators (configured via `classDiscriminator = "type"` in
`plugins/Serialization.kt`) so JSON round-trips both ways. Key types:

- `Card` (`Rank`, `Suit`), `Player`, `TableState`
- `GameAction` sealed class: `Fold` / `Check` / `Call` / `Bet` / `Raise`
- enums: `Rank`, `Suit`, `BettingRound`, `HandRank`, `PlayerStatus`
- `ClientMessage` / `ServerMessage` — the WebSocket envelopes

## Next steps (TODO)

- Implement the real-time poker protocol in `routes/GameSocket.kt` (joins,
  betting actions, redacted table-state broadcasts, per-table concurrency).
- Build a game runtime / hand evaluator behind a `TableService`.
- Back the REST stubs and game runtime with the Exposed schema.
- Add authentication and replace `SchemaUtils` with proper migrations.
- Tighten CORS (`plugins/HTTP.kt`) to an explicit origin allow-list.
