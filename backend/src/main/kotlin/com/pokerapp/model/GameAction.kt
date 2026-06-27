package com.pokerapp.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * An action a player can take when it is their turn to act.
 *
 * Modeled as a sealed class so kotlinx.serialization emits a discriminated
 * union (a `"type"` field) that the Flutter client can pattern-match on. This
 * is the core of the betting protocol exchanged over the game WebSocket.
 *
 * Example JSON for a raise:
 * ```json
 * { "type": "raise", "amount": 200 }
 * ```
 */
@Serializable
sealed class GameAction {

    /** Discard the hand and forfeit any claim to the pot. */
    @Serializable
    @SerialName("fold")
    data object Fold : GameAction()

    /** Pass the action without betting (only legal when there is no bet to call). */
    @Serializable
    @SerialName("check")
    data object Check : GameAction()

    /** Match the current outstanding bet. */
    @Serializable
    @SerialName("call")
    data object Call : GameAction()

    /**
     * Open the betting on a street where no one has bet yet.
     * [amount] is the total chips wagered.
     */
    @Serializable
    @SerialName("bet")
    data class Bet(val amount: Long) : GameAction()

    /**
     * Increase an existing bet.
     * [amount] is the total chips this player is wagering (the "raise to" value),
     * not the increment over the previous bet.
     */
    @Serializable
    @SerialName("raise")
    data class Raise(val amount: Long) : GameAction()
}
