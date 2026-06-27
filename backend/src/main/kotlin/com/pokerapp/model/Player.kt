package com.pokerapp.model

import kotlinx.serialization.Serializable

/**
 * A player seated at a table.
 *
 * [holeCards] is nullable because the server redacts other players' hole cards
 * when projecting a per-player [TableState]: you only ever see your own cards
 * (or everyone's, at showdown).
 */
@Serializable
data class Player(
    val id: String,
    val displayName: String,
    /** Seat index at the table (0-based). */
    val seat: Int,
    /** Remaining chip stack. */
    val stack: Long,
    /** Chips committed to the pot on the current betting round. */
    val currentBet: Long = 0,
    val status: PlayerStatus = PlayerStatus.WAITING,
    /** The player's two private cards, or null when redacted. */
    val holeCards: List<Card>? = null,
)

/**
 * Per-hand state of a seated player.
 */
@Serializable
enum class PlayerStatus {
    /** Seated but not in the current hand (e.g. just joined). */
    WAITING,

    /** Holding cards and still contesting the pot. */
    ACTIVE,

    /** Folded out of the current hand. */
    FOLDED,

    /** All chips committed; no further actions possible this hand. */
    ALL_IN,

    /** Temporarily away; auto-folds when action reaches them. */
    SITTING_OUT,
}
