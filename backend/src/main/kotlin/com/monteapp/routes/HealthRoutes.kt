package com.monteapp.routes

import io.ktor.http.HttpStatusCode
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import kotlinx.serialization.Serializable

/**
 * Liveness/readiness endpoint.
 *
 * GET /health -> 200 { "status": "ok" }
 */
fun Route.healthRoutes() {
    get("/health") {
        call.respond(HttpStatusCode.OK, HealthResponse(status = "ok"))
    }
}

@Serializable
data class HealthResponse(val status: String)
