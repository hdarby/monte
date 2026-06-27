package com.pokerapp.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Messages sent FROM client TO server over the game WebSocket.
 *
 * Discriminated union keyed on `"type"`. This is a draft of the protocol — see
 * the game socket route for the TODOs that will flesh it out.
 */
@Serializable
sealed class ClientMessage {

    /** Request to take a seat at a table. */
    @Serializable
    @SerialName("join")
    data class Join(val tableId: String, val displayName: String) : ClientMessage()

    /** Leave the current table. */
    @Serializable
    @SerialName("leave")
    data object Leave : ClientMessage()

    /** Take a betting action when it's this player's turn. */
    @Serializable
    @SerialName("action")
    data class Action(val action: GameAction) : ClientMessage()
}

/**
 * Messages sent FROM server TO client over the game WebSocket.
 *
 * Discriminated union keyed on `"type"`.
 */
@Serializable
sealed class ServerMessage {

    /** A fresh (redacted) snapshot of the table after some change. */
    @Serializable
    @SerialName("state")
    data class State(val table: TableState) : ServerMessage()

    /** A human-readable / structured error (illegal action, not your turn, ...). */
    @Serializable
    @SerialName("error")
    data class Error(val message: String) : ServerMessage()

    /** Lightweight ack/echo used by the placeholder implementation. */
    @Serializable
    @SerialName("echo")
    data class Echo(val payload: String) : ServerMessage()
}
