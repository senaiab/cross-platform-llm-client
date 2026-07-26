package com.orailnoor.privatelm.opendroid.data.db.dao

import androidx.room.*
import com.orailnoor.privatelm.opendroid.data.db.entities.ModelEntity
import com.orailnoor.privatelm.opendroid.data.db.entities.ModelStatus
import kotlinx.coroutines.flow.Flow

@Dao
interface ModelDao {
    @Query("SELECT * FROM od_models ORDER BY installedAt DESC")
    fun getAllModels(): Flow<List<ModelEntity>>

    @Query("SELECT * FROM od_models WHERE id = :id")
    suspend fun getModelById(id: String): ModelEntity?

    @Query("SELECT * FROM od_models WHERE id = :id")
    fun getModelByIdFlow(id: String): Flow<ModelEntity?>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertModel(model: ModelEntity)

    @Query("UPDATE od_models SET status = :status WHERE id = :id")
    suspend fun updateModelStatus(id: String, status: ModelStatus)

    @Query("UPDATE od_models SET downloadProgress = :progress, status = :status WHERE id = :id")
    suspend fun updateModelProgress(id: String, progress: Int, status: ModelStatus)

    @Query("UPDATE od_models SET downloadProgress = :progress, downloadedSize = :downloadedSize, downloadSpeed = :downloadSpeed, etaString = :eta, status = :status WHERE id = :id")
    suspend fun updateDownloadProgressDetails(id: String, progress: Int, downloadedSize: Long, downloadSpeed: String, eta: String, status: ModelStatus)

    @Query("UPDATE od_models SET lastUsed = :timestamp WHERE id = :id")
    suspend fun updateLastUsed(id: String, timestamp: Long)

    @Query("DELETE FROM od_models WHERE id = :id")
    suspend fun deleteModel(id: String)

    @Query("SELECT * FROM od_models WHERE status = 'READY' ORDER BY lastUsed DESC LIMIT 1")
    suspend fun getRecentlyUsedModel(): ModelEntity?
}
