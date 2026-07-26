package com.orailnoor.privatelm.opendroid.data.db.entities

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "od_notifications")
data class NotificationEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val packageName: String,
    val appName: String,
    val title: String,
    val text: String,
    val timestamp: Long = System.currentTimeMillis(),
    val category: String = "OTHER",
    val isAutoReplied: Boolean = false,
    val autoReplyText: String? = null,
    val contactName: String? = null,
    val senderEmail: String? = null,
    val isRead: Boolean = false
)
