package com.monteapp

import com.monteapp.plugins.configureDatabases
import com.monteapp.plugins.configureHTTP
import com.monteapp.plugins.configureMonitoring
import com.monteapp.plugins.configureRouting
import com.monteapp.plugins.configureSerialization
import com.monteapp.plugins.configureSockets
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
