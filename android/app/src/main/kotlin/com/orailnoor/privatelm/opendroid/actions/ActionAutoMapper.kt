package com.orailnoor.privatelm.opendroid.actions

import android.util.Log

class ActionAutoMapper {

    companion object {
        private const val TAG = "ActionResolver"
        const val SKIP = "SKIP"
    }

    data class MappingResult(
        val originalAction: String,
        val mappedAction: String?,
        val wasMapped: Boolean,
        val mappedParams: Map<String, String>
    )

    fun normalizeActionName(raw: String): String {
        return raw.trim()
            .uppercase()
            .replace(Regex("[\\s]+"), "_")
            .replace("-", "_")
            .replace(Regex("[^A-Z0-9_]"), "")
    }

    private val actionAliases: Map<String, String> = mapOf(
        "NAVIGATE_TO_URL" to "OPEN_URL",
        "OPEN_BROWSER_URL" to "OPEN_URL",
        "BROWSE_WEBSITE" to "OPEN_URL",
        "GO_TO_URL" to "OPEN_URL",
        "VISIT_WEBSITE" to "OPEN_URL",
        "VISIT_URL" to "OPEN_URL",
        "OPEN_LINK" to "OPEN_URL",
        "OPEN_WEBSITE" to "OPEN_URL",
        "NAVIGATE_TO" to "OPEN_URL",
        "SEND_TEXT" to "SEND_SMS",
        "SEND_TEXT_MESSAGE" to "SEND_SMS",
        "TEXT_MESSAGE" to "SEND_SMS",
        "SEND_MESSAGE" to "SEND_WHATSAPP",
        "SEND_WHATSAPP_MESSAGE" to "SEND_WHATSAPP",
        "WHATSAPP" to "SEND_WHATSAPP",
        "CALL" to "MAKE_CALL",
        "PHONE_CALL" to "MAKE_CALL",
        "DIAL" to "MAKE_CALL",
        "CALL_NUMBER" to "MAKE_CALL",
        "VIDEO_CALL" to "MAKE_VIDEO_CALL",
        "OPEN_SETTINGS" to "OPEN_APP",
        "LAUNCH_APP" to "OPEN_APP",
        "START_APP" to "OPEN_APP",
        "SCREENSHOT" to "TAKE_SCREENSHOT",
        "CAPTURE_SCREEN" to "TAKE_SCREENSHOT",
        "SCREEN_CAPTURE" to "TAKE_SCREENSHOT",
        "WIFI" to "TOGGLE_WIFI",
        "TURN_ON_WIFI" to "TOGGLE_WIFI",
        "TURN_OFF_WIFI" to "TOGGLE_WIFI",
        "BLUETOOTH" to "TOGGLE_BLUETOOTH",
        "TURN_ON_BLUETOOTH" to "TOGGLE_BLUETOOTH",
        "TURN_OFF_BLUETOOTH" to "TOGGLE_BLUETOOTH",
        "FLASHLIGHT" to "TOGGLE_FLASHLIGHT",
        "TORCH" to "TOGGLE_FLASHLIGHT",
        "ALARM" to "SET_ALARM",
        "WAKE_ME" to "SET_ALARM",
        "TIMER" to "SET_TIMER",
        "COUNTDOWN" to "SET_TIMER",
        "BRIGHTNESS" to "SET_BRIGHTNESS",
        "SCREEN_BRIGHTNESS" to "SET_BRIGHTNESS",
        "VOLUME" to "SET_VOLUME",
        "SEARCH" to "WEB_SEARCH",
        "GOOGLE" to "WEB_SEARCH",
        "SEARCH_WEB" to "WEB_SEARCH",
        "WEATHER" to "GET_WEATHER",
        "DIRECTIONS" to "GET_DIRECTIONS",
        "MAPS" to "GET_DIRECTIONS",
        "NAVIGATE" to "GET_DIRECTIONS",
        "PLAY" to "PLAY_MUSIC",
        "MUSIC" to "PLAY_MUSIC",
        "PLAY_SONG" to "PLAY_MUSIC",
        "CALCULATE" to "CALCULATE",
        "MATH" to "CALCULATE",
        "TRANSLATE" to "TRANSLATE",
        "LOCK" to "LOCK_SCREEN",
        "SCREEN_OFF" to "LOCK_SCREEN",
        "EMAIL" to "SEND_EMAIL",
        "READ_SCREEN" to "GET_SCREEN_TEXT",
        "SCREEN_TEXT" to "GET_SCREEN_TEXT",
        "CLICK" to "CLICK_TEXT",
        "TAP" to "CLICK_COORDINATES",
        "TYPE" to "TYPE_TEXT",
        "SCROLL_DOWN" to "SCROLL",
        "SCROLL_UP" to "SCROLL",
        "NOTIFICATIONS" to "READ_NOTIFICATIONS",
        "CHECK_NOTIFICATIONS" to "READ_NOTIFICATIONS",
        "MACRO" to "RUN_MACRO",
        "SYSTEM_INFO" to "GET_SYSTEM_INFO",
        "BATTERY" to "GET_SYSTEM_INFO",
        "BATTERY_LEVEL" to "GET_SYSTEM_INFO",
        "CONFIRM" to "ASK_USER",
        "ASK" to "ASK_USER",
        "RESPOND" to "CHAT",
        "REPLY" to "CHAT",
        "SAY" to "CHAT",
        "ANALYZE" to "ANALYZE_SCREENSHOT",
        "READ_SCREEN_WITH_AI" to "ANALYZE_SCREENSHOT"
    )

    fun mapAction(
        action: String,
        params: Map<String, String>,
        registeredActions: Set<String>
    ): MappingResult {
        val normalized = normalizeActionName(action)

        // Direct hit
        if (registeredActions.contains(normalized)) {
            return MappingResult(action, normalized, false, params)
        }

        // Alias table
        val aliased = actionAliases[normalized]
        if (aliased != null) {
            if (aliased == SKIP) {
                return MappingResult(action, null, true, params)
            }
            Log.d(TAG, "Alias resolved: $action → $aliased")
            return MappingResult(action, aliased, true, params)
        }

        // Semantic keyword fallback
        val semantic = semanticFallback(normalized, registeredActions)
        if (semantic != null) {
            Log.d(TAG, "Semantic resolved: $action → $semantic")
            return MappingResult(action, semantic, true, params)
        }

        return MappingResult(action, null, false, params)
    }

    private fun semanticFallback(normalized: String, registeredActions: Set<String>): String? {
        val keywordMap = mapOf(
            "WHATSAPP" to "SEND_WHATSAPP",
            "CALL" to "MAKE_CALL",
            "SMS" to "SEND_SMS",
            "EMAIL" to "SEND_EMAIL",
            "ALARM" to "SET_ALARM",
            "TIMER" to "SET_TIMER",
            "SCREENSHOT" to "TAKE_SCREENSHOT",
            "CAMERA" to "TAKE_PHOTO",
            "MUSIC" to "PLAY_MUSIC",
            "WIFI" to "TOGGLE_WIFI",
            "BLUETOOTH" to "TOGGLE_BLUETOOTH",
            "FLASH" to "TOGGLE_FLASHLIGHT",
            "VOLUME" to "SET_VOLUME",
            "BRIGHTNESS" to "SET_BRIGHTNESS",
            "SEARCH" to "WEB_SEARCH",
            "WEATHER" to "GET_WEATHER",
            "TRANSLATE" to "TRANSLATE",
            "CLICK" to "CLICK_TEXT",
            "TYPE" to "TYPE_TEXT",
            "SCROLL" to "SCROLL",
            "SCREEN" to "GET_SCREEN_TEXT",
            "LOCK" to "LOCK_SCREEN",
            "MACRO" to "RUN_MACRO",
            "NOTIFICATION" to "READ_NOTIFICATIONS",
            "CLIP" to "COPY_TO_CLIPBOARD"
        )

        for ((keyword, action) in keywordMap) {
            if (normalized.contains(keyword) && registeredActions.contains(action)) {
                return action
            }
        }
        return null
    }
}
