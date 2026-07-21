package com.orailnoor.privatelm.executorch

import android.util.Log
import org.pytorch.executorch.extension.llm.LlmCallback
import org.pytorch.executorch.extension.llm.LlmModule

object ExecuTorchBridge {

    private var module: LlmModule? = null

    init {
        try {
            System.loadLibrary("qnn_executorch_backend")
            Log.i("ExecuTorch", "QNN backend loaded")
        } catch (e: UnsatisfiedLinkError) {
            Log.w("ExecuTorch", "QNN backend not available — CPU fallback: ${e.message}")
        }
    }

    fun load(modelPath: String, tokenizerPath: String, temperature: Float): Boolean {
        return try {
            val mod = LlmModule(modelPath, tokenizerPath, temperature)
            val rc = mod.load()
            if (rc != 0) {
                Log.e("ExecuTorch", "LlmModule.load() returned $rc for $modelPath")
                return false
            }
            module = mod
            true
        } catch (t: Throwable) {
            Log.e("ExecuTorch", "LlmModule load failed: ${t.message}")
            module = null
            false
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

    fun stop() {
        runCatching { module?.stop() }
    }

    fun unload() {
        runCatching { module?.resetNative() }
        module = null
    }

    val isLoaded: Boolean get() = module != null
}
