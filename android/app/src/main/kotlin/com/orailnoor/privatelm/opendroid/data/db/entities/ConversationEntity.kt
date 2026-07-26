package com.orailnoor.privatelm.opendroid.data.db.entities

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "od_conversations",
    indices = [Index(value = ["sessionId"])]
)
data class ConversationEntity(
    @PrimaryKey val id: String,
    val text: String,
    val sender: String, // "USER" or "AGENT"
    val timestamp: Long,
    val modelBadge: String? = null,
    val contactPickerData: String? = null,
    val sessionId: String
)
