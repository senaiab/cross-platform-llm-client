package com.orailnoor.privatelm.opendroid.data.db.dao

import androidx.room.*
import com.orailnoor.privatelm.opendroid.data.db.entities.NotificationEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface NotificationDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertNotification(notification: NotificationEntity): Long

    @Query("SELECT * FROM od_notifications ORDER BY timestamp DESC")
    fun getAllNotificationsFlow(): Flow<List<NotificationEntity>>

    @Query("SELECT * FROM od_notifications ORDER BY timestamp DESC LIMIT :limit")
    suspend fun getRecentNotifications(limit: Int = 50): List<NotificationEntity>

    @Query("SELECT * FROM od_notifications WHERE packageName = :packageName ORDER BY timestamp DESC LIMIT :limit")
    suspend fun getNotificationsByApp(packageName: String, limit: Int = 50): List<NotificationEntity>

    @Query("SELECT * FROM od_notifications WHERE contactName = :contactName ORDER BY timestamp DESC LIMIT :limit")
    suspend fun getNotificationsForContact(contactName: String, limit: Int = 20): List<NotificationEntity>

    @Query("SELECT * FROM od_notifications WHERE timestamp > :since ORDER BY timestamp DESC LIMIT :limit")
    suspend fun getNotificationsSince(since: Long, limit: Int = 100): List<NotificationEntity>

    @Query("SELECT * FROM od_notifications WHERE category = 'MESSAGE' AND timestamp > :since ORDER BY timestamp DESC")
    suspend fun getMessageNotificationsSince(since: Long): List<NotificationEntity>

    @Query("UPDATE od_notifications SET isRead = 1 WHERE id = :id")
    suspend fun markAsRead(id: Long)

    @Query("UPDATE od_notifications SET isAutoReplied = 1, autoReplyText = :replyText WHERE id = :id")
    suspend fun markAsAutoReplied(id: Long, replyText: String)

    @Query("SELECT COUNT(*) FROM od_notifications WHERE contactName = :contactName AND isAutoReplied = 1 AND timestamp > :since")
    suspend fun getAutoReplyCountForContact(contactName: String, since: Long): Int

    @Query("DELETE FROM od_notifications WHERE timestamp < :olderThan")
    suspend fun deleteOldNotifications(olderThan: Long)

    @Query("SELECT COUNT(*) FROM od_notifications")
    suspend fun getTotalCount(): Int

    @Delete
    suspend fun deleteNotification(notification: NotificationEntity)

    @Query("DELETE FROM od_notifications")
    suspend fun clearAll()
}
