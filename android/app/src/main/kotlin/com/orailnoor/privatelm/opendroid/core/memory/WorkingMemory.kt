package com.orailnoor.privatelm.opendroid.core.memory

/**
 * Simplified WorkingMemory — holds in-flight conversation context.
 * DeviceStateProvider and Plan are not ported; battery/wifi read stubs return defaults.
 */
class WorkingMemory {

    private val _conversationHistory = mutableListOf<String>()
    val conversationHistory: List<String> get() = _conversationHistory

    var activePlan: String? = null
    var location: String = "Unknown"

    fun addMessage(role: String, content: String) {
        _conversationHistory.add("[$role]: $content")
        if (_conversationHistory.size > 20) {
            _conversationHistory.removeAt(0)
        }
    }

    fun clear() {
        _conversationHistory.clear()
        activePlan = null
    }
}
