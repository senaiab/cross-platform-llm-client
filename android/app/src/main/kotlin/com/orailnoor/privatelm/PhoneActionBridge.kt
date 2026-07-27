package com.orailnoor.privatelm

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import com.orailnoor.privatelm.opendroid.accessibility.CallAutomator
import com.orailnoor.privatelm.opendroid.accessibility.OpenDroidAccessibilityService
import com.orailnoor.privatelm.opendroid.accessibility.SmsAutomator
import com.orailnoor.privatelm.opendroid.accessibility.WhatsAppAutomator
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class PhoneActionBridge(
    private val context: android.content.Context,
    flutterEngine: FlutterEngine
) {
    companion object {
        private const val CHANNEL = "com.orailnoor.privatelm/phone_actions"
        private const val TAG = "PhoneActionBridge"
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private fun isAccessibilityServiceEnabled(): Boolean {
        // Primary check: the service sets its instance on connect and clears on disconnect
        if (OpenDroidAccessibilityService.getInstance() != null) return true
        // Fallback: check system settings (covers cases where instance hasn't been set yet)
        val enabledServices = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabledServices)
        while (splitter.hasNext()) {
            val cn = ComponentName.unflattenFromString(splitter.next()) ?: continue
            if (cn.packageName == context.packageName) return true
        }
        return false
    }

    init {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "isAccessibilityEnabled" -> {
                        result.success(isAccessibilityServiceEnabled())
                    }

                    "openAccessibilitySettings" -> {
                        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(intent)
                        result.success(null)
                    }

                    "sendSms" -> {
                        val to = call.argument<String>("to")
                        val message = call.argument<String>("message")
                        if (to.isNullOrBlank() || message.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "to and message are required", null)
                            return@setMethodCallHandler
                        }
                        scope.launch {
                            try {
                                val success = SmsAutomator.sendSms(context, to, message)
                                withContext(Dispatchers.Main) { result.success(mapOf("success" to success)) }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) { result.error("SMS_ERROR", e.message, null) }
                            }
                        }
                    }

                    "makeCall" -> {
                        val to = call.argument<String>("to")
                        if (to.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "to is required", null)
                            return@setMethodCallHandler
                        }
                        scope.launch {
                            try {
                                val success = CallAutomator.makeCall(context, to)
                                withContext(Dispatchers.Main) { result.success(mapOf("success" to success)) }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) { result.error("CALL_ERROR", e.message, null) }
                            }
                        }
                    }

                    "sendWhatsApp" -> {
                        val contact = call.argument<String>("contact")
                        val message = call.argument<String>("message")
                        if (contact.isNullOrBlank() || message.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "contact and message are required", null)
                            return@setMethodCallHandler
                        }
                        if (!isAccessibilityServiceEnabled()) {
                            result.success(mapOf("success" to false, "error" to "Accessibility service not enabled"))
                            return@setMethodCallHandler
                        }
                        scope.launch {
                            try {
                                // Open WhatsApp chat for the contact first
                                val waIntent = context.packageManager
                                    .getLaunchIntentForPackage("com.whatsapp")
                                    ?.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                                if (waIntent != null) context.startActivity(waIntent)
                                // Then automate the send
                                val success = WhatsAppAutomator.automateSend(message)
                                withContext(Dispatchers.Main) { result.success(mapOf("success" to success)) }
                            } catch (e: Exception) {
                                Log.e(TAG, "sendWhatsApp failed: ${e.message}")
                                withContext(Dispatchers.Main) { result.error("WA_ERROR", e.message, null) }
                            }
                        }
                    }

                    "getScreenText" -> {
                        val svc = OpenDroidAccessibilityService.getInstance()
                        if (svc == null) {
                            result.success("ERROR: Accessibility service not connected")
                        } else {
                            result.success(svc.getScreenText())
                        }
                    }

                    "takeScreenshot" -> {
                        val svc = OpenDroidAccessibilityService.getInstance()
                        if (svc == null) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        scope.launch {
                            val encoded = svc.takeScreenshotAndEncode()
                            withContext(Dispatchers.Main) { result.success(encoded) }
                        }
                    }

                    "clickOnScreen" -> {
                        val x = call.argument<Double>("x")?.toFloat() ?: 0f
                        val y = call.argument<Double>("y")?.toFloat() ?: 0f
                        val svc = OpenDroidAccessibilityService.getInstance()
                        if (svc == null) {
                            result.success(false)
                        } else {
                            result.success(svc.clickCoordinates(x, y))
                        }
                    }

                    "findAndClick" -> {
                        val text = call.argument<String>("text") ?: ""
                        val svc = OpenDroidAccessibilityService.getInstance()
                        if (svc == null) {
                            result.success(false)
                        } else {
                            result.success(svc.findAndClick(text))
                        }
                    }

                    "findAndType" -> {
                        val label = call.argument<String>("text") ?: ""
                        val content = call.argument<String>("content") ?: ""
                        val svc = OpenDroidAccessibilityService.getInstance()
                        if (svc == null) {
                            result.success(false)
                        } else {
                            result.success(svc.findAndType(label, content))
                        }
                    }

                    "openApp" -> {
                        val packageName = call.argument<String>("packageName") ?: ""
                        val intent = context.packageManager.getLaunchIntentForPackage(packageName)
                        if (intent == null) {
                            result.error("NOT_FOUND", "App not installed: $packageName", null)
                        } else {
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            context.startActivity(intent)
                            result.success(null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
