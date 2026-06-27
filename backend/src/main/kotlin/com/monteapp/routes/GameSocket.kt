package com.monteapp.routes

import com.monteapp.model.ClientMessage
import com.monteapp.model.ServerMessage
import com.monteapp.plugins.appJson
import io.ktor.server.routing.Route
import io.ktor.server.websocket.webSocket
import io.ktor.websocket.Frame
import io.ktor.websocket.readText
import kotlinx.serialization.SerializationException

/**
 * The real-time game transport.
 *
 * ws://<host>/ws/game
 *
 * CURRENT BEHAVIOR (placeholder): the server parses each incoming text frame as
 * a [ClientMessage] and replies with a [ServerMessage.Echo]. Unparseable frames
 * get a [ServerMessage.Error]. This exists only to prove the socket + JSON
 * codec wiring end-to-end.
 *
 * --------------------------------------------------------------------------
 * TODO: REAL-TIME POKER PROTOCOL
 * --------------------------------------------------------------------------
 * The full implementation should:
 *
 *  1. AUTHENTICATION / IDENTITY
 *     - Associate the socket with an authenticated user (token in query/header
 *       or a first `auth` message). Reject anonymous sockets.
 *
 *  2. JOINING A TABLE  (ClientMessage.Join)
 *     - Look up the table in the game runtime, seat the player (or add to the
 *       waiting list if full), and register this session as a subscriber so it
 *       receives table-state broadcasts.
 *     - Send the joining player an initial ServerMessage.State.
 *
 *  3. BETTING ACTIONS  (ClientMessage.Action -> GameAction)
 *     - Validate it is this player's turn and the action is legal for the
 *       current BettingRound (e.g. can't Check facing a bet; Raise >= min-raise;
 *       can't bet more than the stack -> coerce to ALL_IN).
 *     - Apply the action to the authoritative hand state, advance the action to
 *       the next eligible seat, and progress the street (deal flop/turn/river,
 *       run showdown, award pot) when the round closes.
 *
 *  4. TABLE-STATE BROADCASTS  (ServerMessage.State)
 *     - After every state change, project a *redacted* TableState per recipient
 *       (each player sees only their own hole cards until showdown) and push it
 *       to every subscribed session for that table.
 *
 *  5. LEAVING / DISCONNECT  (ClientMessage.Leave + socket close)
 *     - Fold the player if mid-hand, free the seat, unsubscribe the session, and
 *       broadcast the updated state. Handle reconnection grace windows.
 *
 *  6. CONCURRENCY
 *     - Serialize mutations per table (e.g. an actor/Mutex per table) so two
 *       sockets can't corrupt hand state. Broadcasts go out via per-session
 *       SendChannels.
 * --------------------------------------------------------------------------
 */
fun Route.gameSocket() {
    webSocket("/ws/game") {
        // TODO: register this session with a SessionManager keyed by table.
        sendServer(ServerMessage.Echo("connected: send a JSON ClientMessage"))

        for (frame in incoming) {
            if (frame !is Frame.Text) continue
            val text = frame.readText()

            val message = try {
                appJson.decodeFromString<ClientMessage>(text)
            } catch (e: SerializationException) {
                sendServer(ServerMessage.Error("malformed message: ${e.message}"))
                continue
            }

            // TODO: dispatch to the game runtime. For now, just echo intent.
            when (message) {
                is ClientMessage.Join ->
                    sendServer(ServerMessage.Echo("join requested for table ${message.tableId} as ${message.displayName}"))

                is ClientMessage.Leave ->
                    sendServer(ServerMessage.Echo("leave requested"))

                is ClientMessage.Action ->
                    sendServer(ServerMessage.Echo("action received: ${message.action}"))
            }
        }

        // TODO: on close, unsubscribe and fold the player if mid-hand.
    }
}

/** Serialize and send a [ServerMessage] as a text frame using the shared codec. */
private suspend fun io.ktor.server.websocket.DefaultWebSocketServerSession.sendServer(message: ServerMessage) {
    send(Frame.Text(appJson.encodeToString<ServerMessage>(message)))
}
