package com.orailnoor.privatelm.opendroid.core.memory

import android.util.Log
import com.orailnoor.privatelm.opendroid.data.db.dao.NotificationDao
import com.orailnoor.privatelm.opendroid.data.db.entities.NotificationEntity

/**
 * Simplified NotificationIntelligence — analyzes notification history for patterns.
 * MemoryRepository is not ported; learned patterns are stored in-memory only.
 */
class NotificationIntelligence(
    private val notificationDao: NotificationDao
) {
    companion object {
        private const val TAG = "NotifIntelligence"
        private const val ANALYSIS_INTERVAL_MS = 6 * 3600 * 1000L // Re-analyze every 6 hours
    }

    private var lastAnalysisTimestamp = 0L
    private val learnedPatterns = mutableMapOf<String, String>()

    /**
     * Run periodic pattern analysis on notification history.
     */
    suspend fun analyzeIfNeeded() {
        val now = System.currentTimeMillis()
        if (now - lastAnalysisTimestamp < ANALYSIS_INTERVAL_MS) return
        lastAnalysisTimestamp = now
        analyzePatterns()
    }

    /**
     * Full pattern analysis — extracts communication patterns from notification history.
     */
    suspend fun analyzePatterns() {
        try {
            val sevenDaysAgo = System.currentTimeMillis() - (7 * 24 * 3600 * 1000L)
            val recentNotifs = notificationDao.getNotificationsSince(sevenDaysAgo, 500)

            if (recentNotifs.isNotEmpty()) {
                analyzeTimePatterns(recentNotifs)
                analyzeTopContacts(recentNotifs)
            }

            val totalCount = notificationDao.getTotalCount()
            learnedPatterns["notification_stats"] = "Total notifications captured: $totalCount."

            Log.d(TAG, "Pattern analysis complete: ${recentNotifs.size} notifications analyzed")
        } catch (e: Exception) {
            Log.e(TAG, "Pattern analysis failed: ${e.message}")
        }
    }

    private fun analyzeTimePatterns(notifications: List<NotificationEntity>) {
        if (notifications.isEmpty()) return

        val hourCounts = IntArray(24)
        for (notif in notifications) {
            val calendar = java.util.Calendar.getInstance().apply { timeInMillis = notif.timestamp }
            hourCounts[calendar.get(java.util.Calendar.HOUR_OF_DAY)]++
        }

        val peakHour = hourCounts.indices.maxByOrNull { hourCounts[it] } ?: 12
        val peakPeriod = when (peakHour) {
            in 6..11 -> "morning"
            in 12..16 -> "afternoon"
            in 17..20 -> "evening"
            else -> "night"
        }
        learnedPatterns["peak_activity"] =
            "User receives most messages in the $peakPeriod (peak hour: $peakHour:00)"
    }

    private fun analyzeTopContacts(notifications: List<NotificationEntity>) {
        val contactCounts = notifications
            .filter { !it.contactName.isNullOrBlank() }
            .groupBy { it.contactName!! }
            .mapValues { it.value.size }
            .entries.sortedByDescending { it.value }
            .take(5)

        if (contactCounts.isNotEmpty()) {
            val summary = contactCounts.joinToString(", ") { "${it.key} (${it.value} messages)" }
            learnedPatterns["top_contacts"] = "Most contacted people this week: $summary"
        }
    }

    /**
     * Get a summary of recent notifications for LLM context.
     */
    suspend fun getRecentNotificationSummary(limit: Int = 10): String {
        return try {
            val recent = notificationDao.getRecentNotifications(limit)
            if (recent.isEmpty()) return "No recent notifications."

            val dateFormat = java.text.SimpleDateFormat("MMM d, h:mm a", java.util.Locale.getDefault())
            recent.joinToString("\n") { notif ->
                val time = dateFormat.format(java.util.Date(notif.timestamp))
                "• ${notif.appName} — ${notif.contactName ?: notif.title}: ${notif.text.take(80)} ($time)"
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to build notification summary: ${e.message}")
            "Unable to retrieve notifications."
        }
    }

    /**
     * Get conversation context for a specific contact from notification history.
     */
    suspend fun buildContactContext(contactName: String): String {
        return try {
            val messages = notificationDao.getNotificationsForContact(contactName)
            if (messages.isEmpty()) return "No previous messages with $contactName."

            messages.sortedBy { it.timestamp }.takeLast(10).joinToString("\n") { msg ->
                "[$contactName]: ${msg.text}"
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to build contact context: ${e.message}")
            ""
        }
    }

    /**
     * Get all learned patterns as a formatted string for LLM context.
     */
    fun getLearnedPatterns(): String {
        if (learnedPatterns.isEmpty()) return ""
        return learnedPatterns.values.joinToString("\n") { "• $it" }
    }

    /**
     * Cleanup old notifications (older than 30 days).
     */
    suspend fun cleanupOldNotifications() {
        try {
            val thirtyDaysAgo = System.currentTimeMillis() - (30L * 24 * 3600 * 1000)
            notificationDao.deleteOldNotifications(thirtyDaysAgo)
            Log.d(TAG, "Cleaned up old notifications")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cleanup notifications: ${e.message}")
        }
    }
}
