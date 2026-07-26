package com.orailnoor.privatelm.opendroid.core.util

object UrlUtils {

    fun formatBaseUrl(rawUrl: String?, fallback: String = ""): String {
        val normalizedInput = normalize(rawUrl)
        if (normalizedInput.isNotEmpty()) return normalizedInput
        return normalize(fallback)
    }

    private fun normalize(url: String?): String {
        var trimmed = url?.trim().orEmpty()
        if (trimmed.isEmpty()) return ""

        trimmed = trimmed.replace(" ", "")
        if (trimmed.isEmpty()) return ""

        val withScheme = if (trimmed.contains("://")) trimmed else "http://$trimmed"

        return withScheme.trimEnd('/')
    }
}
