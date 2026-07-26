package com.orailnoor.privatelm.opendroid.data.db.dao

import androidx.room.*
import com.orailnoor.privatelm.opendroid.data.db.entities.MacroEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface MacroDao {
    @Query("SELECT * FROM od_macros")
    fun getAllMacrosFlow(): Flow<List<MacroEntity>>

    @Query("SELECT * FROM od_macros")
    suspend fun getAllMacros(): List<MacroEntity>

    @Query("SELECT * FROM od_macros WHERE id = :id LIMIT 1")
    suspend fun getMacroById(id: String): MacroEntity?

    @Query("SELECT * FROM od_macros WHERE name = :name LIMIT 1")
    suspend fun getMacroByName(name: String): MacroEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertMacro(macro: MacroEntity)

    @Query("DELETE FROM od_macros WHERE id = :id")
    suspend fun deleteMacro(id: String)

    @Query("DELETE FROM od_macros")
    suspend fun clearAllMacros()
}
