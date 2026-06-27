package com.pokerapp.db

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import io.ktor.server.config.ApplicationConfig
import org.jetbrains.exposed.sql.Database
import org.jetbrains.exposed.sql.SchemaUtils
import org.jetbrains.exposed.sql.transactions.transaction
import org.slf4j.Logger
import javax.sql.DataSource

/**
 * Configures the HikariCP connection pool and Exposed [Database] from HOCON
 * config, then (optionally) creates the schema.
 *
 * DB initialization is GUARDED so the server can boot without Postgres during
 * early development: if `postgres.enabled` is false, or the pool fails to
 * connect, the app logs a warning and continues with persistence disabled.
 */
object DatabaseFactory {

    @Volatile
    var dataSource: DataSource? = null
        private set

    val isInitialized: Boolean
        get() = dataSource != null

    fun init(config: ApplicationConfig, log: Logger) {
        val pg = config.config("postgres")
        val enabled = pg.propertyOrNull("enabled")?.getString()?.toBoolean() ?: false

        if (!enabled) {
            log.warn(
                "Postgres is DISABLED (postgres.enabled=false). " +
                    "Starting without persistence. Set DB_ENABLED=true to enable.",
            )
            return
        }

        try {
            val ds = createHikariDataSource(pg)
            Database.connect(ds)
            dataSource = ds

            // TODO: replace SchemaUtils with a real migration tool (Flyway/Liquibase)
            // before production — create-if-missing is not safe for evolving schemas.
            transaction {
                SchemaUtils.create(Users, Tables, Hands)
            }

            log.info("Database initialized and schema ensured.")
        } catch (e: Exception) {
            log.error(
                "Failed to initialize database — continuing WITHOUT persistence. " +
                    "Is Postgres running and reachable?",
                e,
            )
            dataSource = null
        }
    }

    private fun createHikariDataSource(pg: ApplicationConfig): HikariDataSource {
        val config = HikariConfig().apply {
            jdbcUrl = pg.property("jdbcUrl").getString()
            username = pg.property("user").getString()
            password = pg.property("password").getString()
            driverClassName = pg.propertyOrNull("driver")?.getString() ?: "org.postgresql.Driver"
            maximumPoolSize = pg.propertyOrNull("maxPoolSize")?.getString()?.toInt() ?: 10
            isAutoCommit = false
            transactionIsolation = "TRANSACTION_REPEATABLE_READ"
            validate()
        }
        return HikariDataSource(config)
    }
}
