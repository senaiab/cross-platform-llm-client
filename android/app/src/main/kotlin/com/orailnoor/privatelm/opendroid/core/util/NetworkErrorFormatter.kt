package com.orailnoor.privatelm.opendroid.core.util

object NetworkErrorFormatter {
    fun format(e: Exception): String {
        return when {
            e.message?.contains("timeout", ignoreCase = true) == true ->
                "Network timeout — please check your connection and try again."
            e.message?.contains("unable to resolve host", ignoreCase = true) == true ->
                "Cannot reach the server — check your internet connection."
            e.message?.contains("connection refused", ignoreCase = true) == true ->
                "Connection refused — the server may be down."
            e.message?.contains("ssl", ignoreCase = true) == true ->
                "SSL/TLS error — the connection could not be secured."
            else -> e.message ?: "An unknown network error occurred."
        }
    }
}
