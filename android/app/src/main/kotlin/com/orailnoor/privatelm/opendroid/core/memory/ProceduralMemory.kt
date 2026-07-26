package com.orailnoor.privatelm.opendroid.core.memory

/**
 * Stub — procedural memory (macros/automation routines) not wired in this integration.
 * MemoryRepository and Macro model are not copied from OpenDroid.
 */
class ProceduralMemory {

    suspend fun storeMacro(name: String, steps: List<String>) {
        // No-op
    }

    suspend fun getMacro(name: String): List<String>? = null

    suspend fun listMacros(): List<String> = emptyList()

    fun clear() {
        // No-op
    }
}
