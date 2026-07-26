package com.orailnoor.privatelm.opendroid.accessibility

import android.util.Log
import kotlinx.coroutines.delay

object WhatsAppAutomator {

    suspend fun automateSend(message: String): Boolean {
        val service = OpenDroidAccessibilityService.getInstance() ?: return false

        // Wait for WhatsApp chat screen to fully load
        delay(3000)

        val inputIds = listOf("com.whatsapp:id/entry", "com.whatsapp:id/text_entry")
        var inputFieldFound = false
        for (id in inputIds) {
            val rootNode = service.rootInActiveWindow ?: continue
            val nodes = rootNode.findAccessibilityNodeInfosByViewId(id)
            if (nodes.isNotEmpty()) {
                inputFieldFound = true
                nodes.forEach { it.recycle() }
                break
            }
        }

        if (!inputFieldFound) {
            delay(2000)
            for (id in inputIds) {
                val rootNode = service.rootInActiveWindow ?: continue
                val nodes = rootNode.findAccessibilityNodeInfosByViewId(id)
                if (nodes.isNotEmpty()) {
                    inputFieldFound = true
                    nodes.forEach { it.recycle() }
                    break
                }
            }
            if (!inputFieldFound) {
                Log.w("WhatsAppAutomator", "WhatsApp chat input field not found — not on chat screen")
                return false
            }
        }

        var typed = false
        for (id in inputIds) {
            if (service.findAndTypeById(id, message)) {
                typed = true
                break
            }
        }
        if (!typed) {
            service.findAndType("Type a message", message)
        }

        delay(800)

        val sendButtonIds = listOf(
            "com.whatsapp:id/send",
            "com.whatsapp:id/send_button",
            "com.whatsapp:id/button_send"
        )

        var sendClicked = false
        for (id in sendButtonIds) {
            if (service.findAndClickById(id)) {
                Log.d("WhatsAppAutomator", "Successfully clicked send button by ID: $id")
                sendClicked = true
                break
            }
        }

        if (!sendClicked) {
            sendClicked = service.findAndClick("Send") ||
                          service.findAndClick("send") ||
                          service.findAndClick("SEND")
            if (sendClicked) {
                Log.d("WhatsAppAutomator", "Successfully clicked send button by text label")
            }
        }

        if (!sendClicked) {
            Log.w("WhatsAppAutomator", "Could not click send button automatically")
            return false
        }

        delay(500)
        for (id in inputIds) {
            val rootNode = service.rootInActiveWindow ?: continue
            val nodes = rootNode.findAccessibilityNodeInfosByViewId(id)
            for (node in nodes) {
                val text = node.text?.toString() ?: ""
                node.recycle()
                if (text.isNotBlank() && text != "Type a message" && text != "Message") {
                    Log.w("WhatsAppAutomator", "Post-send check: input field still has text '$text'")
                    return false
                }
            }
        }

        Log.d("WhatsAppAutomator", "Post-send verification passed — message appears to be sent")
        return true
    }
}
