package com.pokerapp.plugins

import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.plugins.cors.routing.CORS

/**
 * Configures CORS.
 *
 * TODO: The Flutter client typically connects from a web origin during
 * development. `anyHost()` is convenient for local dev but MUST be replaced
 * with an explicit allow-list of origins before any production deployment.
 */
fun Application.configureHTTP() {
    install(CORS) {
        allowMethod(HttpMethod.Options)
        allowMethod(HttpMethod.Get)
        allowMethod(HttpMethod.Post)
        allowMethod(HttpMethod.Put)
        allowMethod(HttpMethod.Delete)
        allowHeader(HttpHeaders.ContentType)
        allowHeader(HttpHeaders.Authorization)

        // TODO: replace with allowHost("your-domain", schemes = listOf("https"))
        anyHost()
    }
}
