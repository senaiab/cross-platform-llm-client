package com.orailnoor.privatelm.opendroid.data.db.dao

import androidx.room.*
import com.orailnoor.privatelm.opendroid.data.db.entities.PlanEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface PlanDao {
    @Query("SELECT * FROM od_plans ORDER BY createdAt DESC")
    fun getAllPlansFlow(): Flow<List<PlanEntity>>

    @Query("SELECT * FROM od_plans ORDER BY createdAt DESC")
    suspend fun getAllPlans(): List<PlanEntity>

    @Query("SELECT * FROM od_plans WHERE planId = :planId LIMIT 1")
    suspend fun getPlanById(planId: String): PlanEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertOrUpdatePlan(plan: PlanEntity)

    @Query("DELETE FROM od_plans WHERE planId = :planId")
    suspend fun deletePlan(planId: String)
}
