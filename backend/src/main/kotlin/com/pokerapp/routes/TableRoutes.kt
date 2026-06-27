package com.pokerapp.routes

import com.pokerapp.model.CreateTableRequest
import com.pokerapp.model.TableSummary
import io.ktor.http.HttpStatusCode
import io.ktor.server.request.receive
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.server.routing.route
import java.util.UUID

/**
 * REST endpoints for the lobby: browsing and creating tables.
 *
 * These are STUBS. They return/echo in-memory data and do not yet touch the
 * database or the live game engine.
 *
 * TODO: back these with a TableService that reads/writes via Exposed and
 * coordinates with the in-memory game runtime (see [com.pokerapp.routes.gameSocket]).
 */
fun Route.tableRoutes() {
    route("/api/tables") {

        // GET /api/tables -> list open tables for the lobby.
        get {
            // TODO: query persisted + live tables instead of returning samples.
            val sample = listOf(
                TableSummary(
                    id = "demo-1",
                    name = "Beginner Table",
                    smallBlind = 1,
                    bigBlind = 2,
                    seatedPlayers = 0,
                    maxPlayers = 9,
                ),
                TableSummary(
                    id = "demo-2",
                    name = "High Roller",
                    smallBlind = 25,
                    bigBlind = 50,
                    seatedPlayers = 0,
                    maxPlayers = 6,
                ),
            )
            call.respond(HttpStatusCode.OK, sample)
        }

        // POST /api/tables -> create a new table.
        post {
            val request = call.receive<CreateTableRequest>()
            // TODO: validate blinds/seat count, persist the table, register it
            // with the game runtime, and return the real identifier.
            val created = TableSummary(
                id = UUID.randomUUID().toString(),
                name = request.name,
                smallBlind = request.smallBlind,
                bigBlind = request.bigBlind,
                seatedPlayers = 0,
                maxPlayers = request.maxPlayers,
            )
            call.respond(HttpStatusCode.Created, created)
        }
    }
}
