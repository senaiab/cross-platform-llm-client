package com.orailnoor.privatelm.opendroid.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.orailnoor.privatelm.opendroid.data.db.entities.UnknownActionEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface UnknownActionDao {
    @Query("SELECT * FROM od_unknown_actions ORDER BY timestamp DESC")
    fun getAllUnknownActions(): Flow<List<UnknownActionEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertUnknownAction(unknownAction: UnknownActionEntity)

    @Query("SELECT COUNT(*) FROM od_unknown_actions")
    suspend fun getUnknownActionCount(): Int

    @Query("DELETE FROM od_unknown_actions")
    suspend fun clearAll()
}
