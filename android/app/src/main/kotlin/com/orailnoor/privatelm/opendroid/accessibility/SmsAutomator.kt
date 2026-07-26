package com.orailnoor.privatelm.opendroid.accessibility

import android.content.Context
import android.telephony.SmsManager
import android.util.Log
import kotlinx.coroutines.delay

object SmsAutomator {

    /**
     * Send an SMS directly using SmsManager (requires SEND_SMS permission).
     * Called from PhoneActionBridge when accessibility automation is not needed.
     */
    fun sendSms(context: Context, to: String, message: String): Boolean {
        return try {
            val smsManager = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                context.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
            smsManager?.sendTextMessage(to, null, message, null, null)
            Log.d("SmsAutomator", "SMS sent to $to")
            true
        } catch (e: Exception) {
            Log.e("SmsAutomator", "Failed to send SMS: ${e.message}")
            false
        }
    }

    /**
     * Accessibility-based SMS send — clicks the send button in the currently open SMS app.
     */
    suspend fun automateSend(): Boolean {
        val service = OpenDroidAccessibilityService.getInstance() ?: return false

        delay(1500)

        val sendButtonIds = listOf(
            "com.google.android.apps.messaging:id/send_message_button",
            "com.google.android.apps.messaging:id/send_message_button_icon",
            "com.samsung.android.messaging:id/send_button",
            "com.android.mms:id/send_button",
            "com.google.android.apps.messaging:id/send_button",
            "com.android.messaging:id/send_message_button"
        )

        for (id in sendButtonIds) {
            if (service.findAndClickById(id)) {
                Log.d("SmsAutomator", "Successfully clicked SMS send button by ID: $id")
                return true
            }
        }

        val clicked = service.findAndClick("Send") ||
                      service.findAndClick("send") ||
                      service.findAndClick("SEND") ||
                      service.findAndClick("SMS")

        if (clicked) {
            Log.d("SmsAutomator", "Successfully clicked SMS send button by text label")
            return true
        }

        Log.w("SmsAutomator", "Could not click SMS send button automatically")
        return false
    }
}
