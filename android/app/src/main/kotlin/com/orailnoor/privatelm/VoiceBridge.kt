package com.orailnoor.privatelm

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.orailnoor.privatelm.opendroid.core.voice.TextToSpeechEngine
import com.orailnoor.privatelm.opendroid.core.voice.WakeWordDetector

object VoiceBridge {
    const val METHOD_CHANNEL = "com.orailnoor.privatelm/voice"
    const val EVENT_CHANNEL = "com.orailnoor.privatelm/voice_events"

    private var ttsEngine: TextToSpeechEngine? = null
    private var wakeWordDetector: WakeWordDetector? = null
    private var eventSink: EventChannel.EventSink? = null
    private var wakeWordActive = false

    fun handleMethod(call: MethodCall, result: MethodChannel.Result, context: Context) {
        when (call.method) {
            "initTts" -> {
                if (ttsEngine == null) ttsEngine = TextToSpeechEngine(context)
                result.success(true)
            }
            "speak" -> {
                val text = call.argument<String>("text") ?: return result.error("MISSING", "text required", null)
                if (ttsEngine == null) ttsEngine = TextToSpeechEngine(context)
                ttsEngine?.speak(text)
                result.success(null)
            }
            "stopSpeaking" -> {
                ttsEngine?.stop()
                result.success(null)
            }
            "isSpeaking" -> {
                result.success(false) // Android TTS doesn't expose this easily
            }
            "startWakeWord" -> {
                if (wakeWordActive) return result.success(false)
                if (wakeWordDetector == null) wakeWordDetector = WakeWordDetector(context)
                wakeWordActive = true
                wakeWordDetector?.startListening {
                    android.os.Handler(android.os.Looper.getMainLooper()).post {
                        eventSink?.success(mapOf("event" to "wakeWordDetected"))
                    }
                }
                result.success(true)
            }
            "stopWakeWord" -> {
                wakeWordDetector?.stopListening()
                wakeWordActive = false
                result.success(null)
            }
            "isWakeWordActive" -> {
                result.success(wakeWordActive)
            }
            "destroyTts" -> {
                ttsEngine?.destroy()
                ttsEngine = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }
}
