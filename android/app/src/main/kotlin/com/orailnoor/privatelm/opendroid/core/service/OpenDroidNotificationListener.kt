package com.orailnoor.privatelm.opendroid.core.service

import android.app.Notification
import android.content.pm.PackageManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.orailnoor.privatelm.opendroid.core.memory.NotificationIntelligence
import com.orailnoor.privatelm.opendroid.data.db.OpenDroidDatabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Listens for all system notifications and saves them to the database.
 * Auto-reply logic is stripped (AutoReplyEngine not copied into PrivateLM).
 */
class OpenDroidNotificationListener : NotificationListenerService() {

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private val notificationDao by lazy {
        OpenDroidDatabase.getInstance(applicationContext).notificationDao()
    }

    private val notificationIntelligence by lazy {
        NotificationIntelligence(notificationDao)
    }

    companion object {
        private const val TAG = "NotifListener"
        private const val OWN_PACKAGE = "com.orailnoor.privatelm"

        private val WHATSAPP_PACKAGES = setOf(
            "com.whatsapp", "com.whatsapp.w4b"
        )
        private val SMS_PACKAGES = setOf(
            "com.google.android.apps.messaging",
            "com.android.mms",
            "com.samsung.android.messaging"
        )
        private val EMAIL_PACKAGES = setOf(
            "com.google.android.gm",
            "com.microsoft.office.outlook",
            "com.yahoo.mobile.client.android.mail"
        )

        @Volatile
        private var instance: OpenDroidNotificationListener? = null

        fun getInstance(): OpenDroidNotificationListener? = instance
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        Log.d(TAG, "Notification listener connected")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        instance = null
        Log.d(TAG, "Notification listener disconnected")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return

        if (sbn.packageName == OWN_PACKAGE) return

        val notification = sbn.notification ?: return
        if (notification.flags and Notification.FLAG_ONGOING_EVENT != 0) return
        if (notification.flags and Notification.FLAG_FOREGROUND_SERVICE != 0) return

        serviceScope.launch {
            try {
                val entity = parseNotification(sbn)
                if (entity != null) {
                    val id = notificationDao.insertNotification(entity)
                    Log.d(TAG, "Saved notification: ${entity.appName} — ${entity.title}: ${entity.text.take(50)}")
                    notificationIntelligence.analyzeIfNeeded()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to process notification: ${e.message}")
            }
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        // Optional: track notification dismissals
    }

    override fun onDestroy() {
        super.onDestroy()
        serviceScope.cancel()
        instance = null
    }

    private fun parseNotification(sbn: StatusBarNotification): com.orailnoor.privatelm.opendroid.data.db.entities.NotificationEntity? {
        val notification = sbn.notification ?: return null
        val extras = notification.extras ?: return null

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
            ?: extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString()
            ?: ""

        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
            ?: extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
            ?: ""

        if (title.isBlank() && text.isBlank()) return null

        val appName = getAppName(sbn.packageName)
        val category = classifyNotification(sbn)
        val contactName = extractContactName(sbn, title)
        val senderEmail = if (category == "EMAIL") extractSenderEmail(sbn, title) else null

        return com.orailnoor.privatelm.opendroid.data.db.entities.NotificationEntity(
            packageName = sbn.packageName,
            appName = appName,
            title = title,
            text = text,
            timestamp = sbn.postTime,
            category = category,
            contactName = contactName,
            senderEmail = senderEmail
        )
    }

    private fun getAppName(packageName: String): String {
        return try {
            val pm = applicationContext.packageManager
            val appInfo = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(appInfo).toString()
        } catch (e: PackageManager.NameNotFoundException) {
            packageName.substringAfterLast('.')
        }
    }

    private fun classifyNotification(sbn: StatusBarNotification): String {
        val pkg = sbn.packageName
        return when {
            WHATSAPP_PACKAGES.contains(pkg) -> "MESSAGE"
            SMS_PACKAGES.contains(pkg) -> "MESSAGE"
            EMAIL_PACKAGES.contains(pkg) -> "EMAIL"
            sbn.notification?.category == Notification.CATEGORY_MESSAGE -> "MESSAGE"
            sbn.notification?.category == Notification.CATEGORY_EMAIL -> "EMAIL"
            sbn.notification?.category == Notification.CATEGORY_SOCIAL -> "SOCIAL"
            sbn.notification?.category == Notification.CATEGORY_SYSTEM -> "SYSTEM"
            else -> "OTHER"
        }
    }

    private fun extractContactName(sbn: StatusBarNotification, title: String): String? {
        val extras = sbn.notification?.extras ?: return title.ifBlank { null }
        val messagingPerson = extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString()
        if (!messagingPerson.isNullOrBlank()) return messagingPerson
        return title.ifBlank { null }
    }

    private fun extractSenderEmail(sbn: StatusBarNotification, title: String): String? {
        val extras = sbn.notification?.extras ?: return null
        val emailRegex = Regex("[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}")

        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()
        if (!subText.isNullOrBlank()) {
            emailRegex.find(subText)?.value?.let { return it }
        }

        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
        if (!bigText.isNullOrBlank()) {
            val fromMatch = Regex("(?i)from:?\\s*.*?([a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,})").find(bigText)
            fromMatch?.groupValues?.get(1)?.let { return it }
        }

        emailRegex.find(title)?.value?.let { return it }
        return null
    }

    fun getActiveNotification(packageName: String, contactName: String?): StatusBarNotification? {
        return try {
            val activeNotifications = getActiveNotifications() ?: return null
            activeNotifications.firstOrNull { sbn ->
                sbn.packageName == packageName &&
                sbn.notification?.extras?.let { extras ->
                    val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
                    val convTitle = extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString() ?: ""
                    contactName == null || title == contactName || convTitle == contactName
                } == true &&
                sbn.notification?.actions?.any { it.remoteInputs?.isNotEmpty() == true } == true
            } ?: activeNotifications.firstOrNull { sbn ->
                sbn.packageName == packageName &&
                sbn.notification?.actions?.any { it.remoteInputs?.isNotEmpty() == true } == true
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get active notifications: ${e.message}")
            null
        }
    }
}
