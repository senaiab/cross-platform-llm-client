package com.orailnoor.privatelm.opendroid.data.db.dao

import androidx.room.*
import com.orailnoor.privatelm.opendroid.data.db.entities.ConversationEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ConversationDao {
    @Query("SELECT * FROM od_conversations ORDER BY timestamp ASC")
    fun getAllConversations(): Flow<List<ConversationEntity>>

    @Query("SELECT * FROM od_conversations ORDER BY timestamp DESC LIMIT :limit")
    suspend fun getLastMessages(limit: Int): List<ConversationEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertMessage(message: ConversationEntity)

    @Query("DELETE FROM od_conversations")
    suspend fun clearAll()

    @Query("SELECT * FROM od_conversations WHERE sessionId = :sessionId ORDER BY timestamp ASC")
    fun getMessagesForSession(sessionId: String): Flow<List<ConversationEntity>>

    @Query("SELECT * FROM od_conversations WHERE sessionId = :sessionId ORDER BY timestamp DESC LIMIT :limit")
    suspend fun getLastMessagesForSession(sessionId: String, limit: Int): List<ConversationEntity>

    @Query("DELETE FROM od_conversations WHERE id = :messageId")
    suspend fun deleteMessage(messageId: String)

    @Query("DELETE FROM od_conversations WHERE sessionId = :sessionId")
    suspend fun clearSession(sessionId: String)
}
