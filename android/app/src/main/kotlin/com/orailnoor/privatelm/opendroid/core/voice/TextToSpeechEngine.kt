package com.orailnoor.privatelm.opendroid.core.voice

import android.content.Context
import android.speech.tts.TextToSpeech
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import java.util.Locale

/**
 * Simplified TextToSpeechEngine — uses Android's built-in TTS only.
 * ElevenLabs integration removed (required SettingsRepository which is not copied).
 */
class TextToSpeechEngine(private val context: Context) : TextToSpeech.OnInitListener {

    private var tts: TextToSpeech? = null
    private var isInitialized = false
    private val scope = CoroutineScope(Dispatchers.IO)
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    var onCompletionListener: (() -> Unit)? = null

    init {
        tts = TextToSpeech(context, this)
        tts?.setOnUtteranceProgressListener(object : android.speech.tts.UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}
            override fun onDone(utteranceId: String?) {
                mainHandler.post { onCompletionListener?.invoke() }
            }
            override fun onError(utteranceId: String?) {
                mainHandler.post { onCompletionListener?.invoke() }
            }
        })
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            val result = tts?.setLanguage(Locale.getDefault())
            if (result != TextToSpeech.LANG_MISSING_DATA && result != TextToSpeech.LANG_NOT_SUPPORTED) {
                isInitialized = true
            }
        }
    }

    fun setSpeechRate(rate: Float) {
        tts?.setSpeechRate(rate.coerceIn(0.5f, 3.0f))
    }

    fun speak(text: String) {
        if (isInitialized) {
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "privatelm_tts")
        }
    }

    fun stop() {
        tts?.stop()
    }

    fun destroy() {
        tts?.shutdown()
        tts = null
    }
}
