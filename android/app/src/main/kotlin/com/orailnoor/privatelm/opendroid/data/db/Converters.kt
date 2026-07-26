package com.orailnoor.privatelm.opendroid.data.db

import androidx.room.TypeConverter
import com.orailnoor.privatelm.opendroid.data.db.entities.ModelStatus

class Converters {
    @TypeConverter
    fun fromStatus(status: ModelStatus): String {
        return status.name
    }

    @TypeConverter
    fun toStatus(value: String): ModelStatus {
        return try {
            ModelStatus.valueOf(value)
        } catch (e: Exception) {
            ModelStatus.NOT_DOWNLOADED
        }
    }
}
