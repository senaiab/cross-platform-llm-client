package com.orailnoor.privatelm.executorch

import android.system.Os
import android.util.Log
import org.pytorch.executorch.extension.llm.LlmCallback
import org.pytorch.executorch.extension.llm.LlmModule

object ExecuTorchBridge {

    private var module: LlmModule? = null
    var qnnBackendLoaded: Boolean = false
        private set
    var qnnBackendError: String? = null
        private set

    init {
        // Preload QNN system libraries so the backend's internal dlopen() calls
        // can find them via RTLD_DEFAULT instead of failing on vendor paths.
        for (lib in listOf("QnnSystem", "QnnHtp", "QnnHtpNetRunExtensions", "QnnHtpPrepare")) {
            try {
                System.loadLibrary(lib)
                Log.i("ExecuTorch", "$lib loaded")
            } catch (e: UnsatisfiedLinkError) {
                Log.w("ExecuTorch", "$lib not loaded: ${e.message?.take(120)}")
            }
        }
        try {
            System.loadLibrary("qnn_executorch_backend")
            qnnBackendLoaded = true
            Log.i("ExecuTorch", "QNN backend loaded OK")
        } catch (e: UnsatisfiedLinkError) {
            qnnBackendLoaded = false
            qnnBackendError = e.message
            Log.w("ExecuTorch", "QNN backend load failed: ${e.message}")
        }
    }

    /** Returns null on success, error string on failure. */
    fun load(modelPath: String, tokenizerPath: String, temperature: Float, nativeLibDir: String? = null): String? {
        Log.i("ExecuTorch", "load() qnnBackendLoaded=$qnnBackendLoaded nativeLibDir=$nativeLibDir")
        Log.i("ExecuTorch", "load() modelPath=$modelPath")
        Log.i("ExecuTorch", "load() tokenizerPath=$tokenizerPath")

        // Set ADSP_LIBRARY_PATH so QNN HTP can find skel libraries
        if (nativeLibDir != null) {
            try {
                val existing = System.getenv("ADSP_LIBRARY_PATH")
                val newPath = if (existing.isNullOrEmpty()) nativeLibDir else "$nativeLibDir:$existing"
                Os.setenv("ADSP_LIBRARY_PATH", newPath, true)
                Log.i("ExecuTorch", "ADSP_LIBRARY_PATH=$newPath")
            } catch (e: Exception) {
                Log.w("ExecuTorch", "Could not set ADSP_LIBRARY_PATH: ${e.message}")
            }
        }

        return try {
            val mod = LlmModule(modelPath, tokenizerPath, temperature)
            val rc = mod.load()
            if (rc != 0) {
                val errorName = execuTorchErrorName(rc)
                val msg = "LlmModule.load() rc=$rc ($errorName) — qnnLoaded=$qnnBackendLoaded"
                Log.e("ExecuTorch", msg)
                if (!qnnBackendLoaded) Log.e("ExecuTorch", "QNN backend missing: $qnnBackendError")
                module = null
                msg
            } else {
                module = mod
                Log.i("ExecuTorch", "load() success")
                null
            }
        } catch (t: Throwable) {
            val msg = "LlmModule threw ${t.javaClass.simpleName}: ${t.message}"
            Log.e("ExecuTorch", msg)
            module = null
            msg
        }
    }

    fun generateStream(prompt: String, maxTokens: Int, onToken: (String) -> Unit): Float {
        val mod = module ?: error("No model loaded")
        var tps = 0f
        mod.generate(prompt, maxTokens, object : LlmCallback {
            override fun onResult(token: String) { onToken(token) }
            override fun onStats(tokensPerSecond: Float) { tps = tokensPerSecond }
        })
        return tps
    }

    fun stop() { runCatching { module?.stop() } }

    fun unload() {
        runCatching { module?.resetNative() }
        module = null
    }

    val isLoaded: Boolean get() = module != null

    private fun execuTorchErrorName(rc: Int): String = when (rc) {
        0x00 -> "Ok"
        0x01 -> "Internal"
        0x02 -> "InvalidState"
        0x03 -> "EndOfMethod"
        0x10 -> "NotSupported"
        0x11 -> "NotImplemented"
        0x12 -> "InvalidArgument"
        0x13 -> "InvalidType"
        0x14 -> "OperatorMissing"
        0x20 -> "NotFound"
        0x21 -> "MemoryAllocationFailed"
        0x22 -> "AccessFailed"
        0x23 -> "InvalidProgram"
        0x2C -> "DelegateInvalidCompatibility"
        0x2D -> "DelegateMemoryAllocationFailed"
        0x2E -> "DelegateInvalidHandle"
        else -> "Unknown(0x${rc.toString(16)})"
    }
}
