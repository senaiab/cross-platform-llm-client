package com.orailnoor.privatelm.opendroid.core.memory

/**
 * Stub — semantic memory extraction not wired in this integration.
 * MemoryRepository is not copied from OpenDroid.
 */
class MemoryExtractor {

    suspend fun extractAndStore(text: String) {
        // No-op
    }

    suspend fun getExtractedMemories(): List<String> = emptyList()
}
