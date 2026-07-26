package com.orailnoor.privatelm.opendroid.data.db.entities

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "od_macros")
data class MacroEntity(
    @PrimaryKey val id: String,
    val name: String,
    val trigger: String,
    val stepsJson: String,
    val isSystem: Boolean,
    val isEnabled: Boolean
)
