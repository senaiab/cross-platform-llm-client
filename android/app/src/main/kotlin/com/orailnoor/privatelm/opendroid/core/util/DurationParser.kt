package com.orailnoor.privatelm.opendroid.core.util

object DurationParser {
    /**
     * Parses a human-readable duration string into milliseconds.
     * Examples: "5 minutes", "2 hours", "30 seconds", "1 hour 30 minutes"
     */
    fun parseToMillis(input: String): Long {
        val lower = input.lowercase().trim()
        var totalMs = 0L

        val patterns = listOf(
            Regex("""(\d+(?:\.\d+)?)\s*h(?:our)?s?""") to 3600_000L,
            Regex("""(\d+(?:\.\d+)?)\s*m(?:in(?:ute)?s?)?""") to 60_000L,
            Regex("""(\d+(?:\.\d+)?)\s*s(?:ec(?:ond)?s?)?""") to 1_000L
        )

        for ((regex, multiplier) in patterns) {
            regex.find(lower)?.let { match ->
                val value = match.groupValues[1].toDoubleOrNull() ?: 0.0
                totalMs += (value * multiplier).toLong()
            }
        }

        // Fallback: bare number treated as seconds
        if (totalMs == 0L) {
            val bare = Regex("""^(\d+)$""").find(lower.trim())
            bare?.let { totalMs = (it.groupValues[1].toLongOrNull() ?: 0L) * 1_000L }
        }

        return totalMs
    }
}
