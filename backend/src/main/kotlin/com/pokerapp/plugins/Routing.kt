package com.pokerapp.plugins

import com.pokerapp.routes.gameSocket
import com.pokerapp.routes.healthRoutes
import com.pokerapp.routes.tableRoutes
import io.ktor.server.application.Application
import io.ktor.server.routing.routing

/**
 * Wires up all HTTP and WebSocket routes.
 *
 * Each feature owns its own routing extension under the `routes/` package; this
 * function is the single place where they are mounted.
 */
fun Application.configureRouting() {
    routing {
        healthRoutes()
        tableRoutes()
        gameSocket()
    }
}
