package com.orailnoor.privatelm.opendroid.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.orailnoor.privatelm.opendroid.data.db.dao.ChatSessionDao
import com.orailnoor.privatelm.opendroid.data.db.dao.ConversationDao
import com.orailnoor.privatelm.opendroid.data.db.dao.MacroDao
import com.orailnoor.privatelm.opendroid.data.db.dao.MemoryDao
import com.orailnoor.privatelm.opendroid.data.db.dao.ModelDao
import com.orailnoor.privatelm.opendroid.data.db.dao.NotificationDao
import com.orailnoor.privatelm.opendroid.data.db.dao.PlanDao
import com.orailnoor.privatelm.opendroid.data.db.dao.TaskHistoryDao
import com.orailnoor.privatelm.opendroid.data.db.dao.UnknownActionDao
import com.orailnoor.privatelm.opendroid.data.db.entities.ChatSessionEntity
import com.orailnoor.privatelm.opendroid.data.db.entities.ConversationEntity
import com.orailnoor.privatelm.opendroid.data.db.entities.MacroEntity
import com.orailnoor.privatelm.opendroid.data.db.entities.MemoryEntity
import com.orailnoor.privatelm.opendroid.data.db.entities.ModelEntity
import com.orailnoor.privatelm.opendroid.data.db.entities.NotificationEntity
import com.orailnoor.privatelm.opendroid.data.db.entities.PlanEntity
import com.orailnoor.privatelm.opendroid.data.db.entities.TaskHistoryEntity
import com.orailnoor.privatelm.opendroid.data.db.entities.UnknownActionEntity

@Database(
    entities = [
        ConversationEntity::class,
        ChatSessionEntity::class,
        PlanEntity::class,
        MemoryEntity::class,
        TaskHistoryEntity::class,
        MacroEntity::class,
        UnknownActionEntity::class,
        NotificationEntity::class,
        ModelEntity::class
    ],
    version = 1,
    exportSchema = false
)
@TypeConverters(Converters::class)
abstract class OpenDroidDatabase : RoomDatabase() {
    abstract fun conversationDao(): ConversationDao
    abstract fun chatSessionDao(): ChatSessionDao
    abstract fun planDao(): PlanDao
    abstract fun memoryDao(): MemoryDao
    abstract fun taskHistoryDao(): TaskHistoryDao
    abstract fun macroDao(): MacroDao
    abstract fun unknownActionDao(): UnknownActionDao
    abstract fun notificationDao(): NotificationDao
    abstract fun modelDao(): ModelDao

    companion object {
        @Volatile
        private var instance: OpenDroidDatabase? = null

        fun getInstance(context: Context): OpenDroidDatabase {
            return instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    OpenDroidDatabase::class.java,
                    "opendroid_db"
                )
                    .fallbackToDestructiveMigration()
                    .build()
                    .also { instance = it }
            }
        }
    }
}
