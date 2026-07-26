package com.orailnoor.privatelm.opendroid.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.orailnoor.privatelm.opendroid.data.db.entities.ChatSessionEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ChatSessionDao {
    @Query("SELECT * FROM od_chat_sessions ORDER BY updatedAt DESC")
    fun getAllSessions(): Flow<List<ChatSessionEntity>>

    @Query("SELECT * FROM od_chat_sessions WHERE isCurrent = 1 LIMIT 1")
    fun getCurrentSession(): Flow<ChatSessionEntity?>

    @Query("SELECT * FROM od_chat_sessions WHERE isCurrent = 1 LIMIT 1")
    suspend fun getCurrentSessionOnce(): ChatSessionEntity?

    @Query("SELECT id FROM od_chat_sessions ORDER BY updatedAt DESC LIMIT 1")
    suspend fun getAnySessionId(): String?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(session: ChatSessionEntity)

    @Query("UPDATE od_chat_sessions SET isCurrent = (id = :sessionId)")
    suspend fun markCurrent(sessionId: String)

    @Query("UPDATE od_chat_sessions SET updatedAt = :timestamp WHERE id = :sessionId")
    suspend fun touch(sessionId: String, timestamp: Long)

    @Query("UPDATE od_chat_sessions SET title = :title, updatedAt = :timestamp WHERE id = :sessionId")
    suspend fun rename(sessionId: String, title: String, timestamp: Long)

    @Query("DELETE FROM od_chat_sessions WHERE id = :sessionId")
    suspend fun delete(sessionId: String)
}
