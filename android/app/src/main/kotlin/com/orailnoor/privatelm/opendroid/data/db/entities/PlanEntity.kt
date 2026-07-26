package com.orailnoor.privatelm.opendroid.data.db.entities

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "od_plans")
data class PlanEntity(
    @PrimaryKey val planId: String,
    val goal: String,
    val estimatedDuration: String,
    val estimatedSteps: Int,
    val stepsJson: String,
    val status: String,
    val createdAt: Long
)
