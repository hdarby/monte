package com.pokerapp.plugins

import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import kotlinx.serialization.json.Json

/**
 * Configures JSON (de)serialization for REST endpoints using kotlinx.serialization.
 *
 * The same [Json] configuration is reused by the WebSocket layer so the wire
 * format is identical across transports.
 */
fun Application.configureSerialization() {
    install(ContentNegotiation) {
        json(appJson)
    }
}

/**
 * Shared JSON codec. `ignoreUnknownKeys` keeps the client and server loosely
 * coupled as the protocol evolves; `prettyPrint` is off for compact frames.
 */
val appJson: Json = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
    prettyPrint = false
    classDiscriminator = "type"
}
