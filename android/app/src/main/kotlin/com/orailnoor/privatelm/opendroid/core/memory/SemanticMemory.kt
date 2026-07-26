package com.orailnoor.privatelm.opendroid.core.memory

/**
 * Stub — semantic memory not wired in this integration.
 * MemoryRepository is not copied from OpenDroid.
 */
class SemanticMemory {

    suspend fun store(key: String, value: String) {
        // No-op
    }

    suspend fun recall(key: String): String? = null

    suspend fun search(query: String): List<String> = emptyList()

    fun clear() {
        // No-op
    }
}
