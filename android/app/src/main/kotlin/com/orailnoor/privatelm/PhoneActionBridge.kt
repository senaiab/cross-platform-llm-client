package com.orailnoor.privatelm

import android.content.Context
import android.util.Log
import com.orailnoor.privatelm.opendroid.accessibility.CallAutomator
import com.orailnoor.privatelm.opendroid.accessibility.SmsAutomator
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Flutter MethodChannel bridge that exposes phone action capabilities
 * (SMS, calls) to the Flutter layer via the opendroid automation backend.
 */
class PhoneActionBridge(
    private val context: Context,
    flutterEngine: FlutterEngine
) {
    companion object {
        private const val CHANNEL = "com.orailnoor.privatelm/phone_actions"
        private const val TAG = "PhoneActionBridge"
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    init {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
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
                                withContext(Dispatchers.Main) {
                                    result.success(mapOf("success" to success))
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "sendSms failed: ${e.message}")
                                withContext(Dispatchers.Main) {
                                    result.error("SMS_ERROR", e.message, null)
                                }
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
                                withContext(Dispatchers.Main) {
                                    result.success(mapOf("success" to success))
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "makeCall failed: ${e.message}")
                                withContext(Dispatchers.Main) {
                                    result.error("CALL_ERROR", e.message, null)
                                }
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
