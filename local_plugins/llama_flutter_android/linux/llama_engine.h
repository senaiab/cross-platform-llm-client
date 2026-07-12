#ifndef LLAMA_ENGINE_H_
#define LLAMA_ENGINE_H_

#include <atomic>
#include <functional>
#include <string>
#include <vector>

#include "llama.h"

// Core llama.cpp inference engine, ported from the Android JNI wrapper
// (android/src/main/cpp/jni_wrapper.cpp) with no JNI dependency, so it can
// be driven directly from the Linux GTK plugin on a worker thread.
class LlamaEngine {
 public:
  LlamaEngine() = default;
  ~LlamaEngine();

  struct LoadParams {
    std::string model_path;
    int64_t n_threads = 4;
    int64_t n_ctx = 2048;
    int64_t n_gpu_layers = 0;
  };

  struct GenerateParams {
    std::string prompt;
    int64_t max_tokens = 512;
    double temperature = 0.7;
    double top_p = 0.9;
    int64_t top_k = 40;
    double min_p = 0.05;
    double typical_p = 1.0;
    double repeat_penalty = 1.1;
    double frequency_penalty = 0.0;
    double presence_penalty = 0.0;
    int64_t repeat_last_n = 64;
    int64_t mirostat = 0;
    double mirostat_tau = 5.0;
    double mirostat_eta = 0.1;
    int64_t seed = -1;
    bool penalize_newline = true;
  };

  // Loads a GGUF model. Throws std::runtime_error on failure.
  void LoadModel(const LoadParams& params,
                  const std::function<void(double)>& on_progress);

  // Streams generated text pieces via on_token until EOG, max_tokens, or
  // Stop() is called. Throws std::runtime_error on failure mid-generation
  // (caller should still treat any tokens already emitted as valid output).
  void Generate(const GenerateParams& params,
                const std::function<void(const std::string&)>& on_token);

  void Stop();
  void FreeModel();
  bool IsModelLoaded() const { return model_ != nullptr; }
  int GetTokensUsed() const { return n_past_; }
  int GetContextSize() const { return ctx_ ? llama_n_ctx(ctx_) : 0; }
  void ClearContext();
  void SetSystemPromptLength(int length) { (void)length; }

  bool InitEmbedModel(const std::string& path);
  std::vector<float> Embed(const std::string& text);
  void FreeEmbedModel();

  // Vulkan detection is intentionally not implemented for the Linux v1
  // build (CPU-only), matching the Android build's current posture.
  // Returns false to indicate no GPU info available.
  bool DetectGpu(std::string* out_name, int64_t* out_api_version,
                 int64_t* out_device_local_memory_bytes);

 private:
  llama_model* model_ = nullptr;
  llama_context* ctx_ = nullptr;
  const llama_vocab* vocab_ = nullptr;
  llama_sampler* sampler_ = nullptr;
  std::atomic<bool> stop_flag_{false};
  int n_past_ = 0;

  llama_model* embed_model_ = nullptr;
  llama_context* embed_ctx_ = nullptr;
};

#endif  // LLAMA_ENGINE_H_
