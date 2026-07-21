package com.orailnoor.privatelm.executorch

import android.util.Log
import java.io.File

object QnnDeviceInfo {

    val htpArch: String by lazy {
        val board = runCatching {
            Runtime.getRuntime().exec(arrayOf("getprop", "ro.board.platform"))
                .inputStream.bufferedReader().readLine()?.trim().orEmpty()
        }.getOrElse { "" }.lowercase()

        when {
            "sm8750" in board || "sun" in board       -> "v79"
            "sm8650" in board || "pineapple" in board -> "v75"
            "sm8550" in board || "kalama" in board    -> "v73"
            File("/vendor/lib64/rfs/dsp/snap/libQnnHtpV79Skel.so").exists() -> "v79"
            File("/vendor/lib64/rfs/dsp/snap/libQnnHtpV75Skel.so").exists() -> "v75"
            else -> "v79"
        }
    }

    val systemQnnVersion: String? by lazy {
        val candidates = listOf(
            "/vendor/lib64/snap/libQnnSystem.so",
            "/vendor/lib64/libQnnSystem.so",
            "/vendor/lib64/libsnap_qnn.so",
        )
        for (path in candidates) {
            val result = runCatching {
                val bytes = File(path).inputStream().use { it.readNBytes(2_000_000) }
                val text = String(bytes, Charsets.ISO_8859_1)
                Regex("v(\\d+\\.\\d+\\.\\d+)\\.").find(text)?.groupValues?.get(1)
            }.getOrNull()
            if (result != null) return@lazy result
        }
        null
    }

    val pteSuffix: String get() = "qnn-$htpArch"

    fun logInfo() {
        Log.i("QnnDevice", "arch=$htpArch systemQNN=${systemQnnVersion ?: "unknown"}")
    }
}
