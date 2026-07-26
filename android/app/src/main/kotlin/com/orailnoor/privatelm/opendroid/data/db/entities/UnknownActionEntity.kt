package com.orailnoor.privatelm.opendroid.data.db.entities

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "od_unknown_actions")
data class UnknownActionEntity(
    @PrimaryKey(autoGenerate = true) val id: Int = 0,
    val attemptedAction: String,
    val goal: String,
    val timestamp: Long = System.currentTimeMillis(),
    val fixStatus: String,
    val wasAutoFixed: Boolean = false,
    val fixedWith: String? = null
)
