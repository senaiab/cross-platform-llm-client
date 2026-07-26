package com.orailnoor.privatelm.opendroid.core.memory

import android.content.Context
import android.util.Log

/**
 * Simplified MemoryManager — stores contact preferences in-memory only.
 * Episodic/semantic/procedural storage stubs are no-ops in this integration.
 */
class MemoryManager(private val context: Context) {

    private val contactPreferences = mutableMapOf<String, String>()

    fun recallContactPreference(name: String): String? {
        return contactPreferences[name.lowercase()]
    }

    fun storeContactPreference(name: String, value: String) {
        contactPreferences[name.lowercase()] = value
        Log.d("MemoryManager", "Stored contact preference: $name -> $value")
    }

    fun getUserName(): String? = null

    fun storeMessage(role: String, content: String) {
        // No-op: episodic memory not wired in this integration
    }

    fun clear() {
        contactPreferences.clear()
    }
}
