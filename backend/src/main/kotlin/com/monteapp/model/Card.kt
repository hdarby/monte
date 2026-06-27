package com.monteapp.model

import kotlinx.serialization.Serializable

/**
 * The four French-deck suits.
 *
 * This enum is part of the client/server contract — the Flutter client must
 * mirror these exact names so that JSON (de)serialization round-trips cleanly.
 */
@Serializable
enum class Suit {
    CLUBS,
    DIAMONDS,
    HEARTS,
    SPADES,
}

/**
 * Card ranks from [TWO] (low) to [ACE] (high).
 *
 * The declaration order doubles as the natural ordering used for high-card
 * comparisons. Note that in Texas Hold'em the Ace can also play "low" in a
 * wheel straight (A-2-3-4-5) — that special case is handled by hand-evaluation
 * logic, not by this enum's ordering.
 */
@Serializable
enum class Rank(val shortName: String) {
    TWO("2"),
    THREE("3"),
    FOUR("4"),
    FIVE("5"),
    SIX("6"),
    SEVEN("7"),
    EIGHT("8"),
    NINE("9"),
    TEN("T"),
    JACK("J"),
    QUEEN("Q"),
    KING("K"),
    ACE("A"),
}

/**
 * A single playing card.
 *
 * Cards dealt face-down to other players are never serialized with their real
 * [rank]/[suit] toward a client that should not see them — the server is
 * responsible for redacting hole cards in per-player views of [TableState].
 */
@Serializable
data class Card(
    val rank: Rank,
    val suit: Suit,
)
