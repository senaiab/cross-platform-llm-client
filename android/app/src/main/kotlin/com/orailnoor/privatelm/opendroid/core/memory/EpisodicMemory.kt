package com.orailnoor.privatelm.opendroid.core.memory

/**
 * Stub — episodic memory not wired in this integration.
 * ConversationRepository is not copied from OpenDroid.
 */
class EpisodicMemory {

    fun storeConversation(role: String, content: String) {
        // No-op
    }

    suspend fun getRecentConversations(limit: Int = 10): List<String> = emptyList()

    fun clear() {
        // No-op
    }
}
