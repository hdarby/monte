package com.monteapp.model

import kotlinx.serialization.Serializable

/**
 * Summary view of a table returned by the REST listing endpoint.
 * Cheaper than a full [TableState]; meant for lobby/browse screens.
 */
@Serializable
data class TableSummary(
    val id: String,
    val name: String,
    val smallBlind: Long,
    val bigBlind: Long,
    val seatedPlayers: Int,
    val maxPlayers: Int,
)

/**
 * Request body for creating a new table.
 */
@Serializable
data class CreateTableRequest(
    val name: String,
    val smallBlind: Long,
    val bigBlind: Long,
    val maxPlayers: Int = 9,
)
