package com.monteapp.plugins

import com.monteapp.routes.gameSocket
import com.monteapp.routes.healthRoutes
import com.monteapp.routes.tableRoutes
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
