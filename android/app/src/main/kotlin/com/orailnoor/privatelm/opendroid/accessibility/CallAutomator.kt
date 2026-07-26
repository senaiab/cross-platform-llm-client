package com.orailnoor.privatelm.opendroid.accessibility

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import kotlinx.coroutines.delay

object CallAutomator {

    /**
     * Initiate a phone call directly using Intent.ACTION_CALL (requires CALL_PHONE permission).
     * Called from PhoneActionBridge.
     */
    fun makeCall(context: Context, to: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_CALL, Uri.parse("tel:$to")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            Log.d("CallAutomator", "Call initiated to $to")
            true
        } catch (e: Exception) {
            Log.e("CallAutomator", "Failed to initiate call: ${e.message}")
            false
        }
    }

    /**
     * Accessibility-based call confirmation — clicks the dial button in the currently open dialer.
     */
    suspend fun automateCall(): Boolean {
        val service = OpenDroidAccessibilityService.getInstance() ?: return false

        delay(1500)

        val dialButtonIds = listOf(
            "com.google.android.dialer:id/dialpad_floating_action_button",
            "com.samsung.android.dialer:id/dialButton",
            "com.android.dialer:id/dialpad_floating_action_button",
            "com.android.contacts:id/dialpad_floating_action_button",
            "com.android.phone:id/dialpad_floating_action_button",
            "com.android.dialer:id/dialButton"
        )

        for (id in dialButtonIds) {
            if (service.findAndClickById(id)) {
                Log.d("CallAutomator", "Successfully clicked Dialer call button by ID: $id")
                return true
            }
        }

        val clicked = service.findAndClick("Call") ||
                      service.findAndClick("call") ||
                      service.findAndClick("CALL") ||
                      service.findAndClick("Dial") ||
                      service.findAndClick("dial")

        if (clicked) {
            Log.d("CallAutomator", "Successfully clicked Dialer call button by text label")
            return true
        }

        Log.w("CallAutomator", "Could not click Dialer call button automatically")
        return false
    }
}
