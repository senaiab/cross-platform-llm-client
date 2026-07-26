package com.orailnoor.privatelm.opendroid.data.db.dao

import androidx.room.*
import com.orailnoor.privatelm.opendroid.data.db.entities.TaskHistoryEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface TaskHistoryDao {
    @Query("SELECT * FROM od_task_history ORDER BY timestamp DESC")
    fun getTaskHistoryFlow(): Flow<List<TaskHistoryEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertHistory(task: TaskHistoryEntity)

    @Query("DELETE FROM od_task_history")
    suspend fun clearAll()
}
