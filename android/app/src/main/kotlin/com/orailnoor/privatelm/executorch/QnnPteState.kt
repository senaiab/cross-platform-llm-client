package com.orailnoor.privatelm.executorch

import java.util.concurrent.ConcurrentHashMap

object QnnPteState {
    @Volatile var pteEverSucceeded: Boolean = false

    private val failedPaths = ConcurrentHashMap.newKeySet<String>()
    @Volatile private var backoffUntilMs: Long = 0

    fun recordFailure(path: String) {
        failedPaths.add(path)
        backoffUntilMs = System.currentTimeMillis() + 15 * 60 * 1000L
    }

    fun isBlocked(path: String): Boolean =
        path in failedPaths || System.currentTimeMillis() < backoffUntilMs

    fun reset() {
        failedPaths.clear()
        backoffUntilMs = 0
        pteEverSucceeded = false
    }
}
