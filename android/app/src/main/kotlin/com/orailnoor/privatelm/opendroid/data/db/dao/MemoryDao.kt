package com.orailnoor.privatelm.opendroid.data.db.dao

import androidx.room.*
import com.orailnoor.privatelm.opendroid.data.db.entities.MemoryEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface MemoryDao {
    @Query("SELECT * FROM od_memories")
    fun getAllMemoriesFlow(): Flow<List<MemoryEntity>>

    @Query("SELECT * FROM od_memories")
    suspend fun getAllMemories(): List<MemoryEntity>

    @Query("""SELECT * FROM od_memories
              WHERE ttlHours = -1
              OR (timestamp + (ttlHours * 3600000)) > :now""")
    suspend fun getValidMemories(now: Long = System.currentTimeMillis()): List<MemoryEntity>

    @Query("""SELECT * FROM od_memories
              WHERE type = :type
              AND (ttlHours = -1 OR (timestamp + (ttlHours * 3600000)) > :now)""")
    suspend fun getValidMemoriesByType(type: String, now: Long = System.currentTimeMillis()): List<MemoryEntity>

    @Query("SELECT * FROM od_memories WHERE type = :type")
    suspend fun getMemoriesByType(type: String): List<MemoryEntity>

    @Query("SELECT * FROM od_memories WHERE `key` = :key LIMIT 1")
    suspend fun getMemoryByKey(key: String): MemoryEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertOrUpdateMemory(memory: MemoryEntity)

    @Query("DELETE FROM od_memories WHERE `key` = :key")
    suspend fun deleteMemory(key: String)

    @Query("DELETE FROM od_memories WHERE type = :type")
    suspend fun clearMemoryByType(type: String)

    @Query("""DELETE FROM od_memories
              WHERE ttlHours != -1
              AND (timestamp + (ttlHours * 3600000)) <= :now""")
    suspend fun deleteExpiredMemories(now: Long = System.currentTimeMillis())

    @Query("SELECT * FROM od_memories WHERE `key` LIKE :prefix || '%'")
    suspend fun getMemoriesByKeyPrefix(prefix: String): List<MemoryEntity>

    @Delete
    suspend fun deleteMemoryEntity(memory: MemoryEntity)
}
