package com.orailnoor.privatelm.opendroid.actions

import android.content.Context
import android.util.Log
import com.orailnoor.privatelm.opendroid.actions.base.Action
import com.orailnoor.privatelm.opendroid.actions.base.ActionResult
import com.orailnoor.privatelm.opendroid.data.db.dao.NotificationDao
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Notification actions — AutoReply removed (requires SettingsRepository not copied).
 */
class NotificationActions(private val notificationDao: NotificationDao) {

    fun getActions(): List<Action> = listOf(
        ReadNotificationsAction()
    )

    private inner class ReadNotificationsAction : Action {
        override val name: String = "READ_NOTIFICATIONS"

        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            return try {
                val app = params["app"]
                val count = params["count"]?.toIntOrNull() ?: 10

                val notifications = if (!app.isNullOrBlank()) {
                    val packageFilter = when (app.lowercase()) {
                        "whatsapp" -> "com.whatsapp"
                        "sms", "messages", "messaging" -> "com.google.android.apps.messaging"
                        "gmail", "email" -> "com.google.android.gm"
                        "instagram" -> "com.instagram.android"
                        "telegram" -> "org.telegram.messenger"
                        "twitter", "x" -> "com.twitter.android"
                        else -> app
                    }
                    notificationDao.getNotificationsByApp(packageFilter, count)
                } else {
                    notificationDao.getRecentNotifications(count)
                }

                if (notifications.isEmpty()) {
                    return ActionResult(true, "No notifications found.", null)
                }

                val dateFormat = SimpleDateFormat("MMM d, h:mm a", Locale.getDefault())
                val formatted = notifications.joinToString("\n\n") { notif ->
                    val time = dateFormat.format(Date(notif.timestamp))
                    "[${notif.appName}] $time\nFrom: ${notif.contactName ?: notif.title}\n${notif.text.take(120)}"
                }

                ActionResult(true, "Here are your recent notifications:\n\n$formatted", null)
            } catch (e: Exception) {
                Log.e("NotificationActions", "Failed to read notifications: ${e.message}")
                ActionResult(false, null, "Couldn't read notifications right now.")
            }
        }
    }
}
