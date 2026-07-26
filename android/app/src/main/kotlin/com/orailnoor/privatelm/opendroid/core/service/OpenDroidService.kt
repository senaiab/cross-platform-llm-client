package com.orailnoor.privatelm.opendroid.core.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Minimal foreground service skeleton for the OpenDroid integration.
 * The full agent loop (wake word, speech recognition) is not wired here —
 * those require AgentLoop which is not copied into PrivateLM. This service
 * keeps the process alive and holds the notification channel for future use.
 */
class OpenDroidService : Service() {

    companion object {
        const val ACTION_TRIGGER_RECORD = "com.orailnoor.privatelm.action.TRIGGER_RECORD"
        private const val CHANNEL_ID = "opendroid_channel"
        private const val NOTIFICATION_ID = 2025

        fun start(context: Context) {
            val intent = Intent(context, OpenDroidService::class.java)
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, OpenDroidService::class.java)
            context.stopService(intent)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "PrivateLM Agent Service",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps PrivateLM background agent alive"
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(channel)
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("PrivateLM Active")
            .setContentText("Phone automation service running")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }
}
