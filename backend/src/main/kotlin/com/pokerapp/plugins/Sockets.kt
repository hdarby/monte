package com.pokerapp.plugins

import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.websocket.WebSockets
import io.ktor.server.websocket.pingPeriod
import io.ktor.server.websocket.timeout
import kotlin.time.Duration.Companion.seconds

/**
 * Installs the WebSockets plugin used by the real-time game transport.
 *
 * Routes are registered separately (see [com.pokerapp.plugins.configureRouting]
 * and the `routes/` package).
 */
fun Application.configureSockets() {
    install(WebSockets) {
        pingPeriod = 15.seconds
        timeout = 30.seconds
        maxFrameSize = Long.MAX_VALUE
        masking = false
    }
}
