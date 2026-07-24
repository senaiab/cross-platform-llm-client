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
        // With executorch-android-qnn AAR, libexecutorch.so (JNI bridge) links against
        // libqnn_executorch_backend.so (runtime+QNN), so the Android linker loads
        // libqnn_executorch_backend.so automatically as a dependency — no explicit load needed.
        // Preload QNN vendor libs first so the backend's dlopen() calls find them
        // via RTLD_DEFAULT rather than failing on vendor paths.
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

        // Pre-flight: verify file accessibility
        val pteFile = java.io.File(modelPath)
        Log.i("ExecuTorch", "PTE exists=${pteFile.exists()} size=${pteFile.length()} readable=${pteFile.canRead()}")
        val tokFile = java.io.File(tokenizerPath)
        Log.i("ExecuTorch", "Tokenizer exists=${tokFile.exists()} size=${tokFile.length()} readable=${tokFile.canRead()}")

        // Check for sibling files that might be external constants
        val modelDir = pteFile.parentFile?.absolutePath ?: ""
        val siblings = pteFile.parentFile?.list()?.joinToString(", ") ?: "none"
        Log.i("ExecuTorch", "Model dir: $modelDir — siblings: $siblings")

        // Pre-flight: verify both files are readable before handing off to C++.
        if (!pteFile.exists()) return "PTE file not found: $modelPath"
        if (!pteFile.canRead()) return "PTE file not readable (permission?): $modelPath"
        if (!tokFile.exists()) return "Tokenizer not found: $tokenizerPath"
        if (!tokFile.canRead()) return "Tokenizer not readable (permission?): $tokenizerPath"
        val tokHeader = try {
            val buf = ByteArray(8)
            java.io.FileInputStream(tokFile).use { it.read(buf) }
            buf.joinToString("") { "%02x".format(it) }
        } catch (e: Exception) { "read-err:${e.message?.take(30)}" }
        Log.i("ExecuTorch", "pre-flight OK — pte=${pteFile.length()}B tok=${tokFile.length()}B tokHeader=$tokHeader")

        return try {
            // 3-arg constructor: no dataDir. Passing modelDir as dataDir caused ExecuTorch
            // to scan the directory, find tokenizer.bin, and misinterpret it as external
            // model weight data (wrong format) → AccessFailed. The tokenizer is now
            // copied to internal storage (filesDir/et_models/) before this call.
            val mod = LlmModule(modelPath, tokenizerPath, temperature)
            // executorch-android-qnn 1.3.1: load() returns Unit, throws on failure.
            mod.load()
            module = mod
            Log.i("ExecuTorch", "load() success tokHdr=$tokHeader pte=${pteFile.length()}B tok=${tokFile.length()}B qnn=$qnnBackendLoaded")
            null
        } catch (t: Throwable) {
            val errorCode = try { t.javaClass.getMethod("getErrorCode").invoke(t) as? Int ?: -1 } catch (_: Exception) { -1 }
            val detail = try { t.javaClass.getMethod("getDetailedError").invoke(t)?.toString() ?: "" } catch (_: Exception) { "" }
            val msg = "LlmModule threw ${t.javaClass.simpleName}: rc=$errorCode ${t.message} $detail tokHdr=$tokHeader pte=${pteFile.length()}B tok=${tokFile.length()}B qnn=$qnnBackendLoaded"
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
        })
        return tps
    }

    fun stop() { runCatching { module?.stop() } }

    fun unload() {
        runCatching { module?.resetNative() }
        module = null
    }

    val isLoaded: Boolean get() = module != null

}
