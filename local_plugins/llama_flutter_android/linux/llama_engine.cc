#include "llama_engine.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <ctime>
#include <stdexcept>

namespace {

// Ported from jni_wrapper.cpp's UTF-8 validator/sanitizer.
bool IsValidUtf8(const char* str, size_t len) {
  if (!str) return false;
  const auto* bytes = reinterpret_cast<const unsigned char*>(str);
  size_t i = 0;
  while (i < len) {
    unsigned char c = bytes[i];
    if ((c & 0x80) == 0) {
      i++;
      continue;
    }
    int num_bytes = 0;
    if ((c & 0xE0) == 0xC0) {
      num_bytes = 2;
    } else if ((c & 0xF0) == 0xE0) {
      num_bytes = 3;
    } else if ((c & 0xF8) == 0xF0) {
      num_bytes = 4;
    } else {
      return false;
    }
    if (i + num_bytes > len) return false;
    for (int j = 1; j < num_bytes; j++) {
      if ((bytes[i + j] & 0xC0) != 0x80) return false;
    }
    if (num_bytes == 2) {
      if ((c & 0x1E) == 0) return false;
    } else if (num_bytes == 3) {
      if (c == 0xED && (bytes[i + 1] & 0x20) == 0x20) return false;
      if (c == 0xE0 && (bytes[i + 1] & 0x20) == 0) return false;
    } else if (num_bytes == 4) {
      if (c > 0xF4) return false;
      if (c == 0xF0 && (bytes[i + 1] & 0x30) == 0) return false;
      if (c == 0xF4 && bytes[i + 1] > 0x8F) return false;
    }
    i += num_bytes;
  }
  return true;
}

std::string SanitizeUtf8(const char* str, size_t len) {
  if (!str || len == 0) return "";
  if (IsValidUtf8(str, len)) return std::string(str, len);

  std::string result;
  result.reserve(len);
  const auto* bytes = reinterpret_cast<const unsigned char*>(str);
  size_t i = 0;
  while (i < len) {
    unsigned char c = bytes[i];
    if ((c & 0x80) == 0) {
      result += static_cast<char>(c);
      i++;
      continue;
    }
    int num_bytes = 0;
    if ((c & 0xE0) == 0xC0) {
      num_bytes = 2;
    } else if ((c & 0xF0) == 0xE0) {
      num_bytes = 3;
    } else if ((c & 0xF8) == 0xF0) {
      num_bytes = 4;
    } else {
      result += "\xEF\xBF\xBD";
      i++;
      continue;
    }
    if (i + num_bytes > len) {
      result += "\xEF\xBF\xBD";
      break;
    }
    std::string seq(reinterpret_cast<const char*>(bytes + i), num_bytes);
    if (IsValidUtf8(seq.c_str(), num_bytes)) {
      result += seq;
    } else {
      result += "\xEF\xBF\xBD";
    }
    i += num_bytes;
  }
  return result;
}

}  // namespace

LlamaEngine::~LlamaEngine() {
  FreeEmbedModel();
  FreeModel();
}

void LlamaEngine::LoadModel(const LoadParams& params,
                             const std::function<void(double)>& on_progress) {
  llama_model_params mparams = llama_model_default_params();
  mparams.n_gpu_layers = static_cast<int32_t>(params.n_gpu_layers);

  model_ = llama_model_load_from_file(params.model_path.c_str(), mparams);
  if (!model_) {
    throw std::runtime_error("Failed to load model");
  }

  llama_context_params cparams = llama_context_default_params();
  cparams.n_ctx = static_cast<uint32_t>(params.n_ctx);
  cparams.n_threads = static_cast<int32_t>(params.n_threads);
  cparams.n_threads_batch = static_cast<int32_t>(params.n_threads);
  cparams.n_batch = 512;

  ctx_ = llama_init_from_model(model_, cparams);
  if (!ctx_) {
    llama_model_free(model_);
    model_ = nullptr;
    throw std::runtime_error("Failed to create context");
  }

  vocab_ = llama_model_get_vocab(model_);
  if (!vocab_) {
    llama_free(ctx_);
    llama_model_free(model_);
    ctx_ = nullptr;
    model_ = nullptr;
    throw std::runtime_error("Failed to get vocab from model");
  }

  n_past_ = 0;
  if (on_progress) on_progress(1.0);
}

void LlamaEngine::Generate(
    const GenerateParams& params,
    const std::function<void(const std::string&)>& on_token) {
  if (!model_ || !ctx_ || !vocab_) {
    throw std::runtime_error("Model not loaded");
  }

  stop_flag_ = false;

  std::string sanitized_prompt =
      SanitizeUtf8(params.prompt.c_str(), params.prompt.size());

  const int n_prompt_tokens = -llama_tokenize(
      vocab_, sanitized_prompt.c_str(), (int)sanitized_prompt.size(),
      nullptr, 0, true, true);
  if (n_prompt_tokens <= 0) {
    throw std::runtime_error("Failed to tokenize prompt");
  }
  std::vector<llama_token> tokens(n_prompt_tokens);
  const int actual_tokens = llama_tokenize(
      vocab_, sanitized_prompt.c_str(), (int)sanitized_prompt.size(),
      tokens.data(), (int)tokens.size(), true, true);
  if (actual_tokens < 0) {
    throw std::runtime_error("Failed to tokenize prompt");
  }
  tokens.resize(actual_tokens);

  const int n_ctx = llama_n_ctx(ctx_);
  if (n_past_ + (int)tokens.size() > n_ctx) {
    const int n_discard = n_ctx / 4;
    llama_memory_seq_rm(llama_get_memory(ctx_), 0, 0, n_discard);
    llama_memory_seq_add(llama_get_memory(ctx_), 0, n_discard, n_past_,
                          -n_discard);
    n_past_ -= n_discard;
  }

  const int max_batch_size = 512;
  int tokens_processed = 0;
  llama_batch batch = llama_batch_init(max_batch_size, 0, 1);

  while (tokens_processed < (int)tokens.size()) {
    batch.n_tokens = 0;
    int batch_size =
        std::min((int)tokens.size() - tokens_processed, max_batch_size);
    for (int i = 0; i < batch_size; i++) {
      batch.token[batch.n_tokens] = tokens[tokens_processed + i];
      batch.pos[batch.n_tokens] = n_past_ + tokens_processed + i;
      batch.n_seq_id[batch.n_tokens] = 1;
      batch.seq_id[batch.n_tokens][0] = 0;
      batch.logits[batch.n_tokens] =
          (tokens_processed + i == (int)tokens.size() - 1);
      batch.n_tokens++;
    }
    if (llama_decode(ctx_, batch) != 0) {
      llama_batch_free(batch);
      throw std::runtime_error("Failed to decode prompt");
    }
    tokens_processed += batch_size;
  }
  n_past_ += (int)tokens.size();

  if (sampler_) {
    llama_sampler_free(sampler_);
    sampler_ = nullptr;
  }
  uint32_t sampler_seed = (params.seed >= 0)
                               ? static_cast<uint32_t>(params.seed)
                               : static_cast<uint32_t>(time(nullptr));
  llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
  sampler_ = llama_sampler_chain_init(sparams);

  if (params.repeat_penalty != 1.0 || params.frequency_penalty != 0.0 ||
      params.presence_penalty != 0.0) {
    llama_sampler_chain_add(
        sampler_,
        llama_sampler_init_penalties(
            (int32_t)params.repeat_last_n, (float)params.repeat_penalty,
            (float)params.frequency_penalty, (float)params.presence_penalty));
  }
  llama_sampler_chain_add(sampler_,
                           llama_sampler_init_temp((float)params.temperature));

  if (params.mirostat == 1) {
    llama_sampler_chain_add(
        sampler_, llama_sampler_init_mirostat(
                      llama_vocab_n_tokens(vocab_), sampler_seed,
                      (float)params.mirostat_tau, (float)params.mirostat_eta,
                      100));
  } else if (params.mirostat == 2) {
    llama_sampler_chain_add(
        sampler_, llama_sampler_init_mirostat_v2(
                      sampler_seed, (float)params.mirostat_tau,
                      (float)params.mirostat_eta));
  } else {
    if (params.min_p > 0.0 && params.min_p < 1.0) {
      llama_sampler_chain_add(sampler_,
                               llama_sampler_init_min_p((float)params.min_p, 1));
    }
    if (params.typical_p < 1.0) {
      llama_sampler_chain_add(
          sampler_, llama_sampler_init_typical((float)params.typical_p, 1));
    }
    if (params.top_k > 0) {
      llama_sampler_chain_add(sampler_,
                               llama_sampler_init_top_k((int32_t)params.top_k));
    }
    if (params.top_p < 1.0) {
      llama_sampler_chain_add(sampler_,
                               llama_sampler_init_top_p((float)params.top_p, 1));
    }
  }
  llama_sampler_chain_add(sampler_, llama_sampler_init_dist(sampler_seed));

  for (int i = 0; i < params.max_tokens && !stop_flag_; i++) {
    llama_token new_token_id = llama_sampler_sample(sampler_, ctx_, -1);
    if (llama_vocab_is_eog(vocab_, new_token_id)) break;

    char buffer[256];
    int32_t length =
        llama_token_to_piece(vocab_, new_token_id, buffer, sizeof(buffer), 0, true);
    if (length > 0) {
      std::string piece = SanitizeUtf8(buffer, length);
      if (on_token) on_token(piece);
    }

    batch.n_tokens = 0;
    batch.token[0] = new_token_id;
    batch.pos[0] = n_past_;
    batch.n_seq_id[0] = 1;
    batch.seq_id[0][0] = 0;
    batch.logits[0] = true;
    batch.n_tokens = 1;

    if (llama_decode(ctx_, batch) != 0) break;
    n_past_++;
  }

  llama_batch_free(batch);
}

void LlamaEngine::Stop() { stop_flag_ = true; }

void LlamaEngine::FreeModel() {
  if (sampler_) {
    llama_sampler_free(sampler_);
    sampler_ = nullptr;
  }
  if (ctx_) {
    llama_free(ctx_);
    ctx_ = nullptr;
  }
  if (model_) {
    llama_model_free(model_);
    model_ = nullptr;
  }
  vocab_ = nullptr;
  n_past_ = 0;
}

void LlamaEngine::ClearContext() {
  if (!ctx_) return;
  llama_memory_t mem = llama_get_memory(ctx_);
  if (mem) {
    llama_memory_seq_rm(mem, 0, 0, -1);
    n_past_ = 0;
  }
}

bool LlamaEngine::InitEmbedModel(const std::string& path) {
  FreeEmbedModel();
  llama_model_params mparams = llama_model_default_params();
  mparams.n_gpu_layers = 0;
  embed_model_ = llama_model_load_from_file(path.c_str(), mparams);
  if (!embed_model_) return false;

  llama_context_params cparams = llama_context_default_params();
  cparams.n_ctx = 512;
  cparams.n_threads = 4;
  cparams.embeddings = true;
  embed_ctx_ = llama_init_from_model(embed_model_, cparams);
  if (!embed_ctx_) {
    llama_model_free(embed_model_);
    embed_model_ = nullptr;
    return false;
  }
  return true;
}

std::vector<float> LlamaEngine::Embed(const std::string& text) {
  if (!embed_model_ || !embed_ctx_) return {};

  const llama_vocab* vocab = llama_model_get_vocab(embed_model_);
  const int n_tokens =
      -llama_tokenize(vocab, text.c_str(), (int)text.size(), nullptr, 0, true, true);
  if (n_tokens <= 0) return {};
  std::vector<llama_token> tokens(n_tokens);
  llama_tokenize(vocab, text.c_str(), (int)text.size(), tokens.data(),
                 (int)tokens.size(), true, true);

  llama_memory_seq_rm(llama_get_memory(embed_ctx_), 0, 0, -1);
  llama_batch batch = llama_batch_init(n_tokens, 0, 1);
  batch.n_tokens = n_tokens;
  for (int i = 0; i < n_tokens; i++) {
    batch.token[i] = tokens[i];
    batch.pos[i] = i;
    batch.n_seq_id[i] = 1;
    batch.seq_id[i][0] = 0;
    batch.logits[i] = false;
  }
  if (llama_decode(embed_ctx_, batch) != 0) {
    llama_batch_free(batch);
    return {};
  }
  llama_batch_free(batch);

  const int n_embd = llama_model_n_embd(embed_model_);
  const float* embd = llama_get_embeddings_seq(embed_ctx_, 0);
  if (!embd) embd = llama_get_embeddings_ith(embed_ctx_, n_tokens - 1);
  if (!embd || n_embd <= 0) return {};

  float norm = 0.0f;
  for (int i = 0; i < n_embd; i++) norm += embd[i] * embd[i];
  norm = sqrtf(norm);
  std::vector<float> result(n_embd);
  for (int i = 0; i < n_embd; i++) {
    result[i] = norm > 0 ? embd[i] / norm : 0.0f;
  }
  return result;
}

void LlamaEngine::FreeEmbedModel() {
  if (embed_ctx_) {
    llama_free(embed_ctx_);
    embed_ctx_ = nullptr;
  }
  if (embed_model_) {
    llama_model_free(embed_model_);
    embed_model_ = nullptr;
  }
}

bool LlamaEngine::DetectGpu(std::string* out_name, int64_t* out_api_version,
                             int64_t* out_device_local_memory_bytes) {
  // CPU-only for the Linux v1 build (GGML_VULKAN=OFF) — mirrors Android's
  // current posture of skipping Vulkan probing.
  *out_name = "None";
  *out_api_version = -1;
  *out_device_local_memory_bytes = -1;
  return false;
}
