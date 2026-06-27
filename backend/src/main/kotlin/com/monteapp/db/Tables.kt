package com.monteapp.db

import org.jetbrains.exposed.dao.id.UUIDTable
import org.jetbrains.exposed.sql.javatime.timestamp

/**
 * Exposed table definitions (the persistence schema).
 *
 * These mirror, but are deliberately *not* identical to, the wire DTOs in the
 * `model/` package: the DB stores durable records while the DTOs describe live
 * game state. Keep them decoupled.
 *
 * TODO: add indexes, foreign-key constraints, and migration management (e.g.
 * Flyway) before relying on these in anything beyond local development.
 */

/** Registered users / accounts. */
object Users : UUIDTable("users") {
    val username = varchar("username", 50).uniqueIndex()
    val displayName = varchar("display_name", 100)
    // TODO: store a password hash (argon2/bcrypt), never a plaintext password.
    val passwordHash = varchar("password_hash", 255)
    val chips = long("chips").default(0)
    val createdAt = timestamp("created_at")
}

/** Persisted poker tables (lobby configuration, not live hand state). */
object Tables : UUIDTable("tables") {
    val name = varchar("name", 100)
    val smallBlind = long("small_blind")
    val bigBlind = long("big_blind")
    val maxPlayers = integer("max_players").default(9)
    // TODO: track owner/host (reference Users.id) and lifecycle status.
    val createdAt = timestamp("created_at")
}

/** A record of a completed hand, for history and auditing. */
object Hands : UUIDTable("hands") {
    val tableId = reference("table_id", Tables)
    /** Final community cards, serialized (e.g. "Ah Kd 7c 2s Ts"). */
    val communityCards = varchar("community_cards", 64).nullable()
    val pot = long("pot").default(0)
    // TODO: persist per-player contributions, the winner(s), and the winning
    // hand rank in a related `hand_players` table.
    val startedAt = timestamp("started_at")
    val endedAt = timestamp("ended_at").nullable()
}
