package com.orailnoor.privatelm.opendroid.core.agent

import android.util.Log
import com.orailnoor.privatelm.opendroid.accessibility.OpenDroidAccessibilityService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Simplified VisionEngine — LLM-based analysis is not available in this
 * integration (original used OpenDroid's LLMProviderFactory which is not
 * copied). Instead, screen text is extracted via the accessibility service
 * and returned directly as the "analysis".
 */
class VisionEngine {

    /**
     * Returns the current visible screen text as the analysis result.
     * No actual vision/LLM analysis is performed.
     */
    suspend fun analyzeCurrentScreen(question: String): String = withContext(Dispatchers.Main) {
        val service = OpenDroidAccessibilityService.getInstance()
        if (service == null) {
            Log.w("VisionEngine", "Accessibility service not connected")
            return@withContext "Accessibility service is not running. Enable it in Settings > Accessibility."
        }
        val screenText = service.getScreenText()
        if (screenText.isBlank()) {
            return@withContext "Screen appears empty or inaccessible."
        }
        "Screen content:\n$screenText"
    }

    suspend fun captureScreenBase64(): String? = withContext(Dispatchers.Main) {
        val service = OpenDroidAccessibilityService.getInstance()
        service?.takeScreenshotAndEncode()
    }

    fun getScreenText(): String {
        val service = OpenDroidAccessibilityService.getInstance() ?: return ""
        return service.getScreenText()
    }
}
