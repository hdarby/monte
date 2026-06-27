package com.monteapp.plugins

import com.monteapp.db.DatabaseFactory
import io.ktor.server.application.Application

/**
 * Initializes the database connection pool and schema.
 *
 * DB initialization is intentionally *optional* for now: the scaffold must be
 * able to boot without a running Postgres so the team can iterate on the
 * Flutter client and the protocol. Set `postgres.enabled = true` (or the
 * `DB_ENABLED` env var) once a database is available.
 */
fun Application.configureDatabases() {
    DatabaseFactory.init(environment.config, log)
}
