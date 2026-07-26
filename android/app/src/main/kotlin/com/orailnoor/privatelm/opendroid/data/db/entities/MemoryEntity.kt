package com.orailnoor.privatelm.opendroid.data.db.entities

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "od_memories")
data class MemoryEntity(
    @PrimaryKey val key: String,
    val value: String,
    val type: String, // WORKING, EPISODIC, SEMANTIC, PROCEDURAL
    val timestamp: Long,
    val ttlHours: Int = -1,
    val category: String = "FACT"
)
