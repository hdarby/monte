package com.pokerapp

import com.pokerapp.plugins.configureDatabases
import com.pokerapp.plugins.configureHTTP
import com.pokerapp.plugins.configureMonitoring
import com.pokerapp.plugins.configureRouting
import com.pokerapp.plugins.configureSerialization
import com.pokerapp.plugins.configureSockets
import io.ktor.server.application.Application
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty

/**
 * Entry point.
 *
 * The HTTP port is read from `application.conf` (`ktor.deployment.port`), which
 * in turn honors the `PORT` env var with a default of 8080.
 */
fun main() {
    embeddedServer(
        Netty,
        port = System.getenv("PORT")?.toIntOrNull() ?: 8080,
        host = "0.0.0.0",
        module = Application::module,
    ).start(wait = true)
}

/**
 * Application module: installs every plugin. Each `configureX` lives in its own
 * file under `plugins/` for readability.
 */
fun Application.module() {
    configureMonitoring()      // CallLogging + StatusPages
    configureSerialization()   // ContentNegotiation (kotlinx JSON)
    configureHTTP()            // CORS
    configureSockets()         // WebSockets
    configureDatabases()       // HikariCP + Exposed (optional / guarded)
    configureRouting()         // REST + WebSocket routes
}
