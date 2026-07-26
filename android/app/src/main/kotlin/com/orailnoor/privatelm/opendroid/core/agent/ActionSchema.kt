package com.orailnoor.privatelm.opendroid.core.agent

data class ActionDefinition(
    val name: String,
    val description: String,
    val params: List<ParamDefinition>,
    val examples: List<String>,
    val category: ActionCategory,
    val isSimple: Boolean = true
)

data class ParamDefinition(
    val name: String,
    val type: ParamType,
    val required: Boolean,
    val description: String,
    val enumValues: List<String> = emptyList(),
    val defaultValue: Any? = null
)

enum class ParamType { STRING, INT, BOOLEAN, ENUM }

enum class ActionCategory {
    SYSTEM, COMMUNICATION, PRODUCTIVITY,
    INFORMATION, TRANSPORT, MEDIA,
    SHOPPING, FINANCE, SMART_HOME,
    MACRO, ADVANCED, AGENT, NOTIFICATION
}

object ActionSchema {

    val ALL_ACTIONS = listOf(

        // ── SYSTEM ──────────────────────────────────────

        ActionDefinition(
            name = "OPEN_APP",
            description = "Opens any installed app on the device",
            params = listOf(ParamDefinition("appName", ParamType.STRING, true, "Name of the app to open")),
            examples = listOf("open instagram", "open whatsapp", "launch camera", "start spotify"),
            category = ActionCategory.SYSTEM
        ),
        ActionDefinition(
            name = "TOGGLE_FLASHLIGHT",
            description = "Turns flashlight/torch on, off, or toggles.",
            params = listOf(
                ParamDefinition(
                    name = "state",
                    type = ParamType.ENUM,
                    required = false,
                    description = "Desired flashlight state",
                    enumValues = listOf("on", "off", "toggle"),
                    defaultValue = "toggle"
                )
            ),
            examples = listOf("open flash", "open torch", "turn on flashlight", "torch off"),
            category = ActionCategory.SYSTEM,
            isSimple = true
        ),
        ActionDefinition(
            name = "TAKE_SCREENSHOT",
            description = "Takes a screenshot of current screen",
            params = emptyList(),
            examples = listOf("take screenshot", "screenshot", "capture screen"),
            category = ActionCategory.SYSTEM
        ),
        ActionDefinition(
            name = "LOCK_SCREEN",
            description = "Locks the phone screen",
            params = emptyList(),
            examples = listOf("lock phone", "lock screen", "screen off"),
            category = ActionCategory.SYSTEM
        ),
        ActionDefinition(
            name = "TOGGLE_WIFI",
            description = "Turns WiFi on, off, or toggles.",
            params = listOf(
                ParamDefinition("state", ParamType.ENUM, false, "Desired WiFi state",
                    listOf("on", "off", "toggle"), "toggle")
            ),
            examples = listOf("wifi on", "turn off wifi", "enable wifi"),
            category = ActionCategory.SYSTEM,
            isSimple = true
        ),
        ActionDefinition(
            name = "TOGGLE_BLUETOOTH",
            description = "Turns Bluetooth on, off, or toggles.",
            params = listOf(
                ParamDefinition("state", ParamType.ENUM, false, "Desired Bluetooth state",
                    listOf("on", "off", "toggle"), "toggle")
            ),
            examples = listOf("bluetooth on", "turn off bluetooth"),
            category = ActionCategory.SYSTEM,
            isSimple = true
        ),
        ActionDefinition(
            name = "TOGGLE_MOBILE_DATA",
            description = "Turns mobile data on, off, or toggles.",
            params = listOf(
                ParamDefinition("state", ParamType.ENUM, false, "Desired mobile data state",
                    listOf("on", "off", "toggle"), "toggle")
            ),
            examples = listOf("data on", "turn off mobile data"),
            category = ActionCategory.SYSTEM,
            isSimple = true
        ),
        ActionDefinition(
            name = "SET_BRIGHTNESS",
            description = "Sets screen brightness level.",
            params = listOf(ParamDefinition("level", ParamType.INT, false, "Brightness 0-100", defaultValue = 50)),
            examples = listOf("set brightness to 30", "brightness 60"),
            category = ActionCategory.SYSTEM
        ),
        ActionDefinition(
            name = "SET_VOLUME",
            description = "Sets device volume.",
            params = listOf(
                ParamDefinition("type", ParamType.ENUM, false, "Volume type",
                    listOf("media", "ring", "alarm", "notification", "system"), "media"),
                ParamDefinition("level", ParamType.INT, true, "Volume level 0-100")
            ),
            examples = listOf("set volume to 50", "volume 80"),
            category = ActionCategory.SYSTEM
        ),
        ActionDefinition(
            name = "GET_SYSTEM_INFO",
            description = "Gets system information like battery, storage, RAM",
            params = emptyList(),
            examples = listOf("battery level", "system info", "storage space"),
            category = ActionCategory.SYSTEM
        ),
        ActionDefinition(
            name = "SET_RINGER_MODE",
            description = "Sets ringer mode",
            params = listOf(ParamDefinition("mode", ParamType.ENUM, true, "Ringer mode",
                listOf("normal", "vibrate", "silent"))),
            examples = listOf("vibrate mode", "silent mode"),
            category = ActionCategory.SYSTEM
        ),
        ActionDefinition(
            name = "CLOSE_APP",
            description = "Closes the current foreground app",
            params = emptyList(),
            examples = listOf("close app", "exit app"),
            category = ActionCategory.SYSTEM
        ),
        ActionDefinition(
            name = "ANALYZE_SCREENSHOT",
            description = "Takes screenshot and reads screen content",
            params = listOf(ParamDefinition("question", ParamType.STRING, false, "What to analyze",
                defaultValue = "What do you see on screen?")),
            examples = listOf("what's on my screen", "analyze screen"),
            category = ActionCategory.SYSTEM
        ),
        ActionDefinition(
            name = "OPEN_URL",
            description = "Opens a specific URL/website in the browser.",
            params = listOf(ParamDefinition("url", ParamType.STRING, true, "URL to open")),
            examples = listOf("open google.com", "go to youtube.com"),
            category = ActionCategory.SYSTEM
        ),
        ActionDefinition(
            name = "COPY_TO_CLIPBOARD",
            description = "Copies text to the device clipboard",
            params = listOf(ParamDefinition("text", ParamType.STRING, true, "Text to copy")),
            examples = listOf("copy this to clipboard"),
            category = ActionCategory.SYSTEM
        ),
        ActionDefinition(
            name = "GET_CLIPBOARD",
            description = "Gets the current clipboard content",
            params = emptyList(),
            examples = listOf("what's in clipboard", "show clipboard"),
            category = ActionCategory.SYSTEM
        ),

        // ── COMMUNICATION ───────────────────────────────

        ActionDefinition(
            name = "MAKE_CALL",
            description = "Makes a phone call to a contact or number",
            params = listOf(ParamDefinition("contact", ParamType.STRING, true, "Contact name or phone number")),
            examples = listOf("call dad", "call mom", "call 9876543210"),
            category = ActionCategory.COMMUNICATION
        ),
        ActionDefinition(
            name = "SEND_WHATSAPP",
            description = "Sends WhatsApp message.",
            params = listOf(
                ParamDefinition("contact", ParamType.STRING, true, "Contact name or number"),
                ParamDefinition("message", ParamType.STRING, true, "Message to send")
            ),
            examples = listOf("send hi to dad on whatsapp", "whatsapp mom I'm coming home"),
            category = ActionCategory.COMMUNICATION
        ),
        ActionDefinition(
            name = "SEND_SMS",
            description = "Sends an SMS text message",
            params = listOf(
                ParamDefinition("contact", ParamType.STRING, true, "Contact name or number"),
                ParamDefinition("message", ParamType.STRING, true, "SMS message text")
            ),
            examples = listOf("send sms to dad", "text mom"),
            category = ActionCategory.COMMUNICATION
        ),
        ActionDefinition(
            name = "SEND_EMAIL",
            description = "Sends an email",
            params = listOf(
                ParamDefinition("to", ParamType.STRING, true, "Recipient email or contact name"),
                ParamDefinition("subject", ParamType.STRING, true, "Email subject"),
                ParamDefinition("body", ParamType.STRING, true, "Email body")
            ),
            examples = listOf("send email to boss", "email John"),
            category = ActionCategory.COMMUNICATION,
            isSimple = false
        ),
        ActionDefinition(
            name = "MAKE_VIDEO_CALL",
            description = "Makes a video call via WhatsApp, Meet, or Zoom",
            params = listOf(
                ParamDefinition("contact", ParamType.STRING, true, "Contact name"),
                ParamDefinition("app", ParamType.ENUM, false, "Video call app",
                    listOf("whatsapp", "meet", "zoom"), "whatsapp")
            ),
            examples = listOf("video call mom", "zoom call with team"),
            category = ActionCategory.COMMUNICATION
        ),

        // ── PRODUCTIVITY ────────────────────────────────

        ActionDefinition(
            name = "SET_ALARM",
            description = "Sets an alarm at the specified time.",
            params = listOf(
                ParamDefinition("time", ParamType.STRING, true, "Alarm time"),
                ParamDefinition("label", ParamType.STRING, false, "Alarm label", defaultValue = "Alarm"),
                ParamDefinition("repeat", ParamType.STRING, false, "Repeat pattern", defaultValue = "once")
            ),
            examples = listOf("set alarm 5 am", "wake me at 7"),
            category = ActionCategory.PRODUCTIVITY,
            isSimple = true
        ),
        ActionDefinition(
            name = "SET_TIMER",
            description = "Starts a countdown timer",
            params = listOf(
                ParamDefinition("duration", ParamType.STRING, true, "Timer duration"),
                ParamDefinition("label", ParamType.STRING, false, "Timer label", defaultValue = "Timer")
            ),
            examples = listOf("set timer 5 minutes", "timer 30 seconds"),
            category = ActionCategory.PRODUCTIVITY
        ),
        ActionDefinition(
            name = "CREATE_CALENDAR_EVENT",
            description = "Creates a calendar event",
            params = listOf(
                ParamDefinition("title", ParamType.STRING, true, "Event title"),
                ParamDefinition("date", ParamType.STRING, true, "Event date"),
                ParamDefinition("time", ParamType.STRING, false, "Event time"),
                ParamDefinition("duration", ParamType.STRING, false, "Event duration", defaultValue = "1 hour"),
                ParamDefinition("location", ParamType.STRING, false, "Event location")
            ),
            examples = listOf("create meeting tomorrow 3pm"),
            category = ActionCategory.PRODUCTIVITY,
            isSimple = false
        ),
        ActionDefinition(
            name = "LIST_CALENDAR_TODAY",
            description = "Lists today's calendar events",
            params = emptyList(),
            examples = listOf("what's on my calendar today"),
            category = ActionCategory.PRODUCTIVITY
        ),

        // ── INFORMATION ─────────────────────────────────

        ActionDefinition(
            name = "WEB_SEARCH",
            description = "Searches the web for information",
            params = listOf(ParamDefinition("query", ParamType.STRING, true, "Search query")),
            examples = listOf("search best restaurants", "google latest iphone"),
            category = ActionCategory.INFORMATION
        ),
        ActionDefinition(
            name = "GET_WEATHER",
            description = "Gets current weather for a location",
            params = listOf(
                ParamDefinition("location", ParamType.STRING, false, "City name", defaultValue = "current location"),
                ParamDefinition("days", ParamType.STRING, false, "Forecast days", defaultValue = "1")
            ),
            examples = listOf("weather today", "weather in Addis Ababa"),
            category = ActionCategory.INFORMATION
        ),
        ActionDefinition(
            name = "CALCULATE",
            description = "Performs a mathematical calculation",
            params = listOf(ParamDefinition("expression", ParamType.STRING, true, "Math expression")),
            examples = listOf("calculate 15% of 2000", "what is 45 * 12"),
            category = ActionCategory.INFORMATION
        ),
        ActionDefinition(
            name = "TRANSLATE",
            description = "Translates text to another language",
            params = listOf(
                ParamDefinition("text", ParamType.STRING, true, "Text to translate"),
                ParamDefinition("from", ParamType.STRING, false, "Source language"),
                ParamDefinition("to", ParamType.STRING, true, "Target language")
            ),
            examples = listOf("translate hello to Amharic"),
            category = ActionCategory.INFORMATION
        ),

        // ── TRANSPORT ───────────────────────────────────

        ActionDefinition(
            name = "GET_DIRECTIONS",
            description = "Gets directions to a destination",
            params = listOf(
                ParamDefinition("to", ParamType.STRING, true, "Destination"),
                ParamDefinition("from", ParamType.STRING, false, "Starting point"),
                ParamDefinition("mode", ParamType.ENUM, false, "Travel mode",
                    listOf("drive", "walk", "transit", "bike"), "drive")
            ),
            examples = listOf("directions to airport", "how to reach mall"),
            category = ActionCategory.TRANSPORT
        ),

        // ── MEDIA ───────────────────────────────────────

        ActionDefinition(
            name = "PLAY_MUSIC",
            description = "Plays music on Spotify or YouTube",
            params = listOf(
                ParamDefinition("query", ParamType.STRING, true, "Song, artist, or playlist name"),
                ParamDefinition("app", ParamType.ENUM, false, "Music app",
                    listOf("spotify", "youtube", "local"), "spotify")
            ),
            examples = listOf("play Arijit Singh", "play Bollywood hits"),
            category = ActionCategory.MEDIA
        ),
        ActionDefinition(
            name = "TAKE_PHOTO",
            description = "Takes a photo using camera",
            params = listOf(ParamDefinition("camera", ParamType.ENUM, false, "Camera",
                listOf("back", "front"), "back")),
            examples = listOf("take photo", "take selfie"),
            category = ActionCategory.MEDIA
        ),

        // ── ADVANCED ────────────────────────────────────

        ActionDefinition(
            name = "LIST_FILES",
            description = "Lists files in a directory",
            params = listOf(ParamDefinition("path", ParamType.STRING, true, "Directory path")),
            examples = listOf("list files in downloads"),
            category = ActionCategory.ADVANCED
        ),
        ActionDefinition(
            name = "READ_FILE",
            description = "Reads contents of a file",
            params = listOf(ParamDefinition("filePath", ParamType.STRING, true, "File path")),
            examples = listOf("read file", "open document"),
            category = ActionCategory.ADVANCED
        ),
        ActionDefinition(
            name = "CLICK_TEXT",
            description = "Clicks on screen element by visible text",
            params = listOf(ParamDefinition("text", ParamType.STRING, true, "Text to click on")),
            examples = listOf("click on Settings"),
            category = ActionCategory.ADVANCED
        ),
        ActionDefinition(
            name = "CLICK_ID",
            description = "Clicks on screen element by view ID",
            params = listOf(ParamDefinition("viewId", ParamType.STRING, true, "View ID to click")),
            examples = listOf("click button with id"),
            category = ActionCategory.ADVANCED
        ),
        ActionDefinition(
            name = "TYPE_TEXT",
            description = "Types text into a field found by search text",
            params = listOf(
                ParamDefinition("searchText", ParamType.STRING, true, "Text to find the field"),
                ParamDefinition("content", ParamType.STRING, true, "Content to type")
            ),
            examples = listOf("type in search box"),
            category = ActionCategory.ADVANCED
        ),
        ActionDefinition(
            name = "SCROLL",
            description = "Scrolls the screen",
            params = listOf(ParamDefinition("direction", ParamType.ENUM, true, "Scroll direction",
                listOf("forward", "backward"))),
            examples = listOf("scroll down", "scroll up"),
            category = ActionCategory.ADVANCED
        ),
        ActionDefinition(
            name = "GET_SCREEN_TEXT",
            description = "Reads all visible text on screen",
            params = emptyList(),
            examples = listOf("read screen text", "get screen content"),
            category = ActionCategory.ADVANCED
        ),
        ActionDefinition(
            name = "CLICK_COORDINATES",
            description = "Clicks at specific screen coordinates",
            params = listOf(
                ParamDefinition("x", ParamType.STRING, true, "X coordinate"),
                ParamDefinition("y", ParamType.STRING, true, "Y coordinate")
            ),
            examples = listOf("click at position"),
            category = ActionCategory.ADVANCED
        ),
        ActionDefinition(
            name = "PRESS_ENTER",
            description = "Performs the IME enter/search action on the focused field.",
            params = emptyList(),
            examples = listOf("press enter", "submit the search"),
            category = ActionCategory.ADVANCED
        ),
        ActionDefinition(
            name = "WAIT",
            description = "Pauses execution for a short duration.",
            params = listOf(
                ParamDefinition("durationMs", ParamType.INT, false, "Milliseconds to wait, max 10000",
                    defaultValue = 2000)
            ),
            examples = listOf("wait 2 seconds", "wait for the app to load"),
            category = ActionCategory.ADVANCED
        ),

        // ── MACRO ───────────────────────────────────────

        ActionDefinition(
            name = "RUN_MACRO",
            description = "Runs a saved macro",
            params = listOf(ParamDefinition("macroName", ParamType.STRING, true, "Macro name")),
            examples = listOf("run morning routine"),
            category = ActionCategory.MACRO
        ),
        ActionDefinition(
            name = "CREATE_MACRO",
            description = "Creates a new macro",
            params = listOf(
                ParamDefinition("name", ParamType.STRING, true, "Macro name"),
                ParamDefinition("steps", ParamType.STRING, true, "JSON steps definition")
            ),
            examples = listOf("create morning routine macro"),
            category = ActionCategory.MACRO,
            isSimple = false
        ),

        // ── AGENT ───────────────────────────────────────

        ActionDefinition(
            name = "ASK_USER",
            description = "Asks user for missing information",
            params = listOf(
                ParamDefinition("question", ParamType.STRING, true, "Question to ask user"),
                ParamDefinition("options", ParamType.STRING, false, "Comma-separated options", defaultValue = "")
            ),
            examples = emptyList(),
            category = ActionCategory.AGENT
        ),
        ActionDefinition(
            name = "CHAT",
            description = "Responds conversationally without device action",
            params = listOf(ParamDefinition("response", ParamType.STRING, true, "Conversational response")),
            examples = listOf("how are you", "tell me a joke"),
            category = ActionCategory.AGENT
        ),

        // ── NOTIFICATION ────────────────────────────────

        ActionDefinition(
            name = "READ_NOTIFICATIONS",
            description = "Reads recent notifications from the device.",
            params = listOf(
                ParamDefinition("app", ParamType.STRING, false, "App name to filter", defaultValue = ""),
                ParamDefinition("count", ParamType.STRING, false, "Number of notifications", defaultValue = "10")
            ),
            examples = listOf("read my notifications", "show whatsapp messages"),
            category = ActionCategory.NOTIFICATION
        )
    )

    fun getAllActionNames(): List<String> = ALL_ACTIONS.map { it.name }.sorted()

    fun getAction(name: String): ActionDefinition? = ALL_ACTIONS.find { it.name == name }

    fun isValid(name: String): Boolean = ALL_ACTIONS.any { it.name == name }

    fun getByCategory(category: ActionCategory): List<ActionDefinition> =
        ALL_ACTIONS.filter { it.category == category }

    fun getSimpleActions(): List<String> = ALL_ACTIONS.filter { it.isSimple }.map { it.name }

    fun applyDefaults(actionName: String, params: Map<String, Any>): Map<String, Any> {
        val definition = getAction(actionName) ?: return params
        val result = params.toMutableMap()
        definition.params.forEach { paramDef ->
            if (!result.containsKey(paramDef.name) && paramDef.defaultValue != null) {
                result[paramDef.name] = paramDef.defaultValue
            }
        }
        return result
    }

    fun validateParams(
        actionName: String,
        params: Map<String, Any>
    ): Pair<ValidationResult, Map<String, Any>> {
        val definition = getAction(actionName)
            ?: return Pair(ValidationResult.InvalidAction(actionName), params)

        val enrichedParams = params.toMutableMap()
        val missingRequired = mutableListOf<String>()

        definition.params.forEach { paramDef ->
            val value = enrichedParams[paramDef.name]
            when {
                value != null -> {
                    if (paramDef.type == ParamType.ENUM && paramDef.enumValues.isNotEmpty()) {
                        val strValue = value.toString().lowercase()
                        val validValues = paramDef.enumValues.map { it.lowercase() }
                        if (!validValues.contains(strValue)) {
                            val fixed = fixEnumValue(strValue, paramDef.enumValues)
                            if (fixed != null) enrichedParams[paramDef.name] = fixed
                            else missingRequired.add(paramDef.name)
                        }
                    }
                }
                paramDef.defaultValue != null -> enrichedParams[paramDef.name] = paramDef.defaultValue
                paramDef.required -> missingRequired.add(paramDef.name)
                else -> {}
            }
        }

        return if (missingRequired.isEmpty()) {
            Pair(ValidationResult.Valid, enrichedParams)
        } else {
            Pair(ValidationResult.MissingParams(missingRequired), enrichedParams)
        }
    }

    private fun fixEnumValue(input: String, validValues: List<String>): String? {
        validValues.find { it.lowercase() == input.lowercase() }?.let { return it }
        val synonyms = mapOf(
            "yes" to "on", "enable" to "on", "activate" to "on", "true" to "on", "start" to "on",
            "no" to "off", "disable" to "off", "deactivate" to "off", "false" to "off", "stop" to "off",
            "switch" to "toggle", "flip" to "toggle", "change" to "toggle"
        )
        val synonym = synonyms[input.lowercase()]
        return validValues.find { it.lowercase() == synonym?.lowercase() }
    }

    sealed class ValidationResult {
        object Valid : ValidationResult()
        data class InvalidAction(val name: String) : ValidationResult()
        data class MissingParams(val params: List<String>) : ValidationResult()
    }
}
