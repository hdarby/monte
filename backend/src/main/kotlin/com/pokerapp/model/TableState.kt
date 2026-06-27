package com.pokerapp.model

import kotlinx.serialization.Serializable

/**
 * A snapshot of a table broadcast to clients.
 *
 * The server holds the authoritative state and emits a redacted projection of
 * this to each connected player after every meaningful change (a player joins,
 * an action is taken, the street advances, etc.). See the game WebSocket route
 * for the real-time protocol.
 */
@Serializable
data class TableState(
    val tableId: String,
    val name: String,
    val players: List<Player>,
    /** Community cards revealed so far (0, 3, 4, or 5). */
    val communityCards: List<Card> = emptyList(),
    /** Total chips in the pot (main + side pots collapsed for display). */
    val pot: Long = 0,
    val smallBlind: Long,
    val bigBlind: Long,
    val bettingRound: BettingRound = BettingRound.PRE_FLOP,
    /** Seat index of the dealer button. */
    val dealerSeat: Int = 0,
    /** Seat of the player who must act next, or null if the hand is idle. */
    val activeSeat: Int? = null,
)
