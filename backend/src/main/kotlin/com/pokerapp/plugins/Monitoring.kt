package com.pokerapp.plugins

import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.plugins.calllogging.CallLogging
import io.ktor.server.plugins.statuspages.StatusPages
import io.ktor.server.request.path
import io.ktor.server.response.respond
import kotlinx.serialization.Serializable
import org.slf4j.event.Level

/**
 * Installs request logging and a global error handler.
 *
 * [StatusPages] converts uncaught exceptions into structured JSON so the client
 * always receives a predictable error shape instead of an HTML stack trace.
 */
fun Application.configureMonitoring() {
    install(CallLogging) {
        level = Level.INFO
        filter { call -> call.request.path().startsWith("/") }
    }

    install(StatusPages) {
        exception<Throwable> { call, cause ->
            call.application.log.error("Unhandled exception", cause)
            call.respond(
                HttpStatusCode.InternalServerError,
                ErrorResponse(error = "internal_error", message = cause.message ?: "Unexpected error"),
            )
        }
    }
}

@Serializable
data class ErrorResponse(val error: String, val message: String)
