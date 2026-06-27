package com.pokerapp.model

import kotlinx.serialization.Serializable

/**
 * The streets of a Texas Hold'em hand.
 *
 * [PRE_FLOP] -> [FLOP] -> [TURN] -> [RIVER] -> [SHOWDOWN].
 */
@Serializable
enum class BettingRound {
    PRE_FLOP,
    FLOP,
    TURN,
    RIVER,
    SHOWDOWN,
}

/**
 * Poker hand categories ordered from weakest ([HIGH_CARD]) to strongest
 * ([ROYAL_FLUSH]). Declaration order is significant for comparison.
 */
@Serializable
enum class HandRank {
    HIGH_CARD,
    PAIR,
    TWO_PAIR,
    THREE_OF_A_KIND,
    STRAIGHT,
    FLUSH,
    FULL_HOUSE,
    FOUR_OF_A_KIND,
    STRAIGHT_FLUSH,
    ROYAL_FLUSH,
}
