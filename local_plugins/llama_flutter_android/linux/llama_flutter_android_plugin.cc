#include "include/llama_flutter_android/llama_flutter_android_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <sys/sysinfo.h>

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "chat_templates.h"
#include "llama_engine.h"
#include "llama_message_codec.h"

#define LLAMA_FLUTTER_ANDROID_PLUGIN(obj)                       \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), llama_flutter_android_plugin_get_type(), \
                              LlamaFlutterAndroidPlugin))

struct _LlamaFlutterAndroidPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(LlamaFlutterAndroidPlugin, llama_flutter_android_plugin,
              g_object_get_type())

namespace {

const char kChannelPrefix[] = "dev.flutter.pigeon.llama_flutter_android.";

LlamaEngine* g_engine = nullptr;
std::string g_current_model_path;
std::mutex g_engine_mutex;
std::atomic<bool> g_is_stopping{false};

FlBasicMessageChannel* g_flutter_api_on_token = nullptr;
FlBasicMessageChannel* g_flutter_api_on_done = nullptr;
FlBasicMessageChannel* g_flutter_api_on_error = nullptr;
FlBasicMessageChannel* g_flutter_api_on_load_progress = nullptr;

// ---- Main-thread marshaling ----
// All Flutter engine calls (channel send/respond) must happen on the
// platform thread. llama.cpp work runs on a detached worker thread, so
// callbacks post back via g_idle_add, mirroring the Kotlin implementation's
// withContext(Dispatchers.Main).

gboolean RunOnMainThread(gpointer data) {
  auto* fn = static_cast<std::function<void()>*>(data);
  (*fn)();
  delete fn;
  return G_SOURCE_REMOVE;
}

void PostToMainThread(std::function<void()> fn) {
  g_idle_add(RunOnMainThread, new std::function<void()>(std::move(fn)));
}

// ---- FlutterApi senders (native -> Dart) ----

void SendOnToken(const std::string& token) {
  g_autoptr(FlValue) msg = fl_value_new_list();
  fl_value_append_take(msg, fl_value_new_string(token.c_str()));
  fl_basic_message_channel_send(g_flutter_api_on_token, msg, nullptr, nullptr,
                                 nullptr);
}

void SendOnDone() {
  fl_basic_message_channel_send(g_flutter_api_on_done, nullptr, nullptr,
                                 nullptr, nullptr);
}

void SendOnError(const std::string& error) {
  g_autoptr(FlValue) msg = fl_value_new_list();
  fl_value_append_take(msg, fl_value_new_string(error.c_str()));
  fl_basic_message_channel_send(g_flutter_api_on_error, msg, nullptr, nullptr,
                                 nullptr);
}

void SendOnLoadProgress(double progress) {
  g_autoptr(FlValue) msg = fl_value_new_list();
  fl_value_append_take(msg, fl_value_new_float(progress));
  fl_basic_message_channel_send(g_flutter_api_on_load_progress, msg, nullptr,
                                 nullptr, nullptr);
}

// ---- HostApi reply helpers ----

void RespondSuccess(FlBasicMessageChannel* channel,
                     FlBasicMessageChannelResponseHandle* handle,
                     FlValue* result_or_null) {
  g_autoptr(FlValue) reply = fl_value_new_list();
  fl_value_append_take(reply, result_or_null ? result_or_null
                                              : fl_value_new_null());
  fl_basic_message_channel_respond(channel, handle, reply, nullptr);
}

void RespondError(FlBasicMessageChannel* channel,
                   FlBasicMessageChannelResponseHandle* handle,
                   const std::string& code, const std::string& message) {
  g_autoptr(FlValue) reply = fl_value_new_list();
  fl_value_append_take(reply, fl_value_new_string(code.c_str()));
  fl_value_append_take(reply, fl_value_new_string(message.c_str()));
  fl_value_append_take(reply, fl_value_new_null());
  fl_basic_message_channel_respond(channel, handle, reply, nullptr);
}

// ---- Argument decoding helpers ----

FlValue* UnwrapCustom(FlValue* v) {
  return const_cast<FlValue*>(
      static_cast<const FlValue*>(fl_value_get_custom_value(v)));
}

int64_t GetIntOrDefault(FlValue* list, size_t idx, int64_t def) {
  FlValue* v = fl_value_get_list_value(list, idx);
  if (v == nullptr || fl_value_get_type(v) == FL_VALUE_TYPE_NULL) return def;
  return fl_value_get_int(v);
}

double GetDouble(FlValue* list, size_t idx) {
  return fl_value_get_float(fl_value_get_list_value(list, idx));
}

bool GetBool(FlValue* list, size_t idx) {
  return fl_value_get_bool(fl_value_get_list_value(list, idx));
}

std::string GetString(FlValue* list, size_t idx) {
  FlValue* v = fl_value_get_list_value(list, idx);
  if (v == nullptr || fl_value_get_type(v) == FL_VALUE_TYPE_NULL) return "";
  const gchar* s = fl_value_get_string(v);
  return s ? std::string(s) : "";
}

// Fills the 15 shared generation fields (maxTokens..penalizeNewline) that
// GenerateRequest and ChatRequest both carry, starting at `max_tokens_idx`.
void FillGenerationParams(FlValue* list, size_t max_tokens_idx,
                           LlamaEngine::GenerateParams* out) {
  size_t i = max_tokens_idx;
  out->max_tokens = GetIntOrDefault(list, i + 0, 512);
  out->temperature = GetDouble(list, i + 1);
  out->top_p = GetDouble(list, i + 2);
  out->top_k = GetIntOrDefault(list, i + 3, 40);
  out->min_p = GetDouble(list, i + 4);
  out->typical_p = GetDouble(list, i + 5);
  out->repeat_penalty = GetDouble(list, i + 6);
  out->frequency_penalty = GetDouble(list, i + 7);
  out->presence_penalty = GetDouble(list, i + 8);
  out->repeat_last_n = GetIntOrDefault(list, i + 9, 64);
  out->mirostat = GetIntOrDefault(list, i + 10, 0);
  out->mirostat_tau = GetDouble(list, i + 11);
  out->mirostat_eta = GetDouble(list, i + 12);
  out->seed = GetIntOrDefault(list, i + 13, -1);
  out->penalize_newline = GetBool(list, i + 14);
}

LlamaEngine::LoadParams DecodeModelConfig(FlValue* custom) {
  FlValue* fields = UnwrapCustom(custom);
  LlamaEngine::LoadParams p;
  p.model_path = GetString(fields, 0);
  p.n_threads = GetIntOrDefault(fields, 1, 4);
  p.n_ctx = GetIntOrDefault(fields, 2, 2048);
  p.n_gpu_layers = GetIntOrDefault(fields, 3, 0);
  return p;
}

TemplateChatMessage DecodeChatMessage(FlValue* custom) {
  FlValue* fields = UnwrapCustom(custom);
  TemplateChatMessage m;
  m.role = GetString(fields, 0);
  m.content = GetString(fields, 1);
  return m;
}

LlamaEngine::GenerateParams DecodeGenerateRequest(FlValue* custom) {
  FlValue* fields = UnwrapCustom(custom);
  LlamaEngine::GenerateParams params;
  params.prompt = GetString(fields, 0);
  FillGenerationParams(fields, 1, &params);
  return params;
}

struct DecodedChatRequest {
  std::vector<TemplateChatMessage> messages;
  std::string template_name;
  LlamaEngine::GenerateParams params;
};

DecodedChatRequest DecodeChatRequest(FlValue* custom) {
  FlValue* fields = UnwrapCustom(custom);
  DecodedChatRequest req;
  FlValue* msgs_list = fl_value_get_list_value(fields, 0);
  size_t n = fl_value_get_length(msgs_list);
  for (size_t i = 0; i < n; i++) {
    req.messages.push_back(DecodeChatMessage(fl_value_get_list_value(msgs_list, i)));
  }
  req.template_name = GetString(fields, 1);
  FillGenerationParams(fields, 2, &req.params);
  return req;
}

// ---- Generation (shared by generate/generateChat) ----

void RunGeneration(FlBasicMessageChannel* channel,
                    FlBasicMessageChannelResponseHandle* response_handle,
                    std::shared_ptr<LlamaEngine::GenerateParams> params) {
  g_object_ref(response_handle);
  g_object_ref(channel);
  std::thread([channel, response_handle, params]() {
    std::lock_guard<std::mutex> lock(g_engine_mutex);
    bool ok = true;
    std::string error_message;
    try {
      g_engine->Generate(*params, [](const std::string& token) {
        if (!g_is_stopping.load()) {
          PostToMainThread([token] { SendOnToken(token); });
        }
      });
    } catch (const std::exception& e) {
      ok = false;
      error_message = e.what();
    }
    bool stopping = g_is_stopping.load();
    PostToMainThread([channel, response_handle, ok, error_message, stopping]() {
      if (!stopping) {
        if (ok) {
          SendOnDone();
        } else {
          SendOnError(error_message);
        }
      }
      if (ok || stopping) {
        RespondSuccess(channel, response_handle, nullptr);
      } else {
        RespondError(channel, response_handle, "GenerationError", error_message);
      }
      g_object_unref(response_handle);
      g_object_unref(channel);
    });
  }).detach();
}

// ---- HostApi handlers ----

void HandleLoadModel(FlBasicMessageChannel* channel, FlValue* message,
                      FlBasicMessageChannelResponseHandle* response_handle,
                      gpointer user_data) {
  auto params = std::make_shared<LlamaEngine::LoadParams>(
      DecodeModelConfig(fl_value_get_list_value(message, 0)));

  g_object_ref(response_handle);
  g_object_ref(channel);
  std::thread([channel, response_handle, params]() {
    std::lock_guard<std::mutex> lock(g_engine_mutex);
    bool ok = true;
    std::string error_message;
    try {
      g_engine->LoadModel(*params, [](double p) {
        PostToMainThread([p] { SendOnLoadProgress(p); });
      });
      g_current_model_path = params->model_path;
    } catch (const std::exception& e) {
      ok = false;
      error_message = e.what();
    }
    PostToMainThread([channel, response_handle, ok, error_message]() {
      if (ok) {
        RespondSuccess(channel, response_handle, nullptr);
      } else {
        SendOnError(error_message);
        RespondError(channel, response_handle, "LoadModelError", error_message);
      }
      g_object_unref(response_handle);
      g_object_unref(channel);
    });
  }).detach();
}

void HandleGenerate(FlBasicMessageChannel* channel, FlValue* message,
                     FlBasicMessageChannelResponseHandle* response_handle,
                     gpointer user_data) {
  if (!g_engine->IsModelLoaded()) {
    RespondError(channel, response_handle, "IllegalStateException",
                 "Model not loaded");
    return;
  }
  auto params = std::make_shared<LlamaEngine::GenerateParams>(
      DecodeGenerateRequest(fl_value_get_list_value(message, 0)));
  g_is_stopping = false;
  RunGeneration(channel, response_handle, params);
}

void HandleGenerateChat(FlBasicMessageChannel* channel, FlValue* message,
                         FlBasicMessageChannelResponseHandle* response_handle,
                         gpointer user_data) {
  if (!g_engine->IsModelLoaded()) {
    RespondError(channel, response_handle, "IllegalStateException",
                 "Model not loaded");
    return;
  }
  DecodedChatRequest decoded =
      DecodeChatRequest(fl_value_get_list_value(message, 0));
  auto params =
      std::make_shared<LlamaEngine::GenerateParams>(decoded.params);
  params->prompt = ChatTemplateManager::Instance().FormatMessages(
      decoded.messages, decoded.template_name, g_current_model_path);
  g_is_stopping = false;
  RunGeneration(channel, response_handle, params);
}

void HandleGetSupportedTemplates(
    FlBasicMessageChannel* channel, FlValue* message,
    FlBasicMessageChannelResponseHandle* response_handle, gpointer user_data) {
  auto templates = ChatTemplateManager::Instance().GetSupportedTemplates();
  FlValue* list = fl_value_new_list();
  for (const auto& t : templates) {
    fl_value_append_take(list, fl_value_new_string(t.c_str()));
  }
  RespondSuccess(channel, response_handle, list);
}

void HandleStop(FlBasicMessageChannel* channel, FlValue* message,
                 FlBasicMessageChannelResponseHandle* response_handle,
                 gpointer user_data) {
  g_is_stopping = true;
  g_engine->Stop();
  RespondSuccess(channel, response_handle, nullptr);
}

void HandleDispose(FlBasicMessageChannel* channel, FlValue* message,
                    FlBasicMessageChannelResponseHandle* response_handle,
                    gpointer user_data) {
  g_is_stopping = true;
  g_engine->Stop();
  {
    std::lock_guard<std::mutex> lock(g_engine_mutex);
    g_engine->FreeModel();
  }
  RespondSuccess(channel, response_handle, nullptr);
}

void HandleIsModelLoaded(FlBasicMessageChannel* channel, FlValue* message,
                          FlBasicMessageChannelResponseHandle* response_handle,
                          gpointer user_data) {
  RespondSuccess(channel, response_handle,
                 fl_value_new_bool(g_engine->IsModelLoaded()));
}

void HandleGetContextInfo(
    FlBasicMessageChannel* channel, FlValue* message,
    FlBasicMessageChannelResponseHandle* response_handle, gpointer user_data) {
  int tokens_used = g_engine->GetTokensUsed();
  int context_size = g_engine->GetContextSize();
  double usage =
      context_size > 0 ? (double)tokens_used / context_size * 100.0 : 0.0;
  FlValue* fields = fl_value_new_list();
  fl_value_append_take(fields, fl_value_new_int(tokens_used));
  fl_value_append_take(fields, fl_value_new_int(context_size));
  fl_value_append_take(fields, fl_value_new_float(usage));
  RespondSuccess(channel, response_handle,
                 llama_codec_wrap_custom(LLAMA_CODEC_TYPE_CONTEXT_INFO, fields));
}

void HandleClearContext(FlBasicMessageChannel* channel, FlValue* message,
                         FlBasicMessageChannelResponseHandle* response_handle,
                         gpointer user_data) {
  g_engine->ClearContext();
  RespondSuccess(channel, response_handle, nullptr);
}

void HandleSetSystemPromptLength(
    FlBasicMessageChannel* channel, FlValue* message,
    FlBasicMessageChannelResponseHandle* response_handle, gpointer user_data) {
  int64_t length = GetIntOrDefault(message, 0, 0);
  g_engine->SetSystemPromptLength((int)length);
  RespondSuccess(channel, response_handle, nullptr);
}

void HandleRegisterCustomTemplate(
    FlBasicMessageChannel* channel, FlValue* message,
    FlBasicMessageChannelResponseHandle* response_handle, gpointer user_data) {
  std::string name = GetString(message, 0);
  std::string content = GetString(message, 1);
  ChatTemplateManager::Instance().RegisterCustomTemplate(name, content);
  RespondSuccess(channel, response_handle, nullptr);
}

void HandleUnregisterCustomTemplate(
    FlBasicMessageChannel* channel, FlValue* message,
    FlBasicMessageChannelResponseHandle* response_handle, gpointer user_data) {
  std::string name = GetString(message, 0);
  ChatTemplateManager::Instance().UnregisterCustomTemplate(name);
  RespondSuccess(channel, response_handle, nullptr);
}

void HandleDetectGpu(FlBasicMessageChannel* channel, FlValue* message,
                      FlBasicMessageChannelResponseHandle* response_handle,
                      gpointer user_data) {
  // CPU-only for the Linux v1 build — see LlamaEngine::DetectGpu.
  std::string name;
  int64_t api_version = -1;
  int64_t device_mem = -1;
  g_engine->DetectGpu(&name, &api_version, &device_mem);

  int64_t free_ram = -1;
  struct sysinfo info;
  if (sysinfo(&info) == 0) {
    free_ram = static_cast<int64_t>(info.freeram) * info.mem_unit;
  }

  FlValue* fields = fl_value_new_list();
  fl_value_append_take(fields, fl_value_new_bool(false));
  fl_value_append_take(fields, fl_value_new_string(name.c_str()));
  fl_value_append_take(fields, fl_value_new_int(api_version));
  fl_value_append_take(fields, fl_value_new_int(device_mem));
  fl_value_append_take(fields, fl_value_new_int(free_ram));
  fl_value_append_take(fields, fl_value_new_int(0));
  RespondSuccess(channel, response_handle,
                 llama_codec_wrap_custom(LLAMA_CODEC_TYPE_GPU_INFO, fields));
}

}  // namespace

static void llama_flutter_android_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(llama_flutter_android_plugin_parent_class)->dispose(object);
}

static void llama_flutter_android_plugin_class_init(
    LlamaFlutterAndroidPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = llama_flutter_android_plugin_dispose;
}

static void llama_flutter_android_plugin_init(LlamaFlutterAndroidPlugin* self) {}

void llama_flutter_android_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  LlamaFlutterAndroidPlugin* plugin = LLAMA_FLUTTER_ANDROID_PLUGIN(
      g_object_new(llama_flutter_android_plugin_get_type(), nullptr));

  if (g_engine == nullptr) g_engine = new LlamaEngine();

  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);
  g_autoptr(LlamaMessageCodec) codec = llama_message_codec_new();

  auto register_channel = [&](const char* method,
                               FlBasicMessageChannelMessageHandler handler) {
    std::string name = std::string(kChannelPrefix) + "LlamaHostApi." + method;
    FlBasicMessageChannel* channel = fl_basic_message_channel_new(
        messenger, name.c_str(), FL_MESSAGE_CODEC(codec));
    fl_basic_message_channel_set_message_handler(
        channel, handler, g_object_ref(plugin), g_object_unref);
  };

  register_channel("loadModel", HandleLoadModel);
  register_channel("generate", HandleGenerate);
  register_channel("generateChat", HandleGenerateChat);
  register_channel("getSupportedTemplates", HandleGetSupportedTemplates);
  register_channel("stop", HandleStop);
  register_channel("dispose", HandleDispose);
  register_channel("isModelLoaded", HandleIsModelLoaded);
  register_channel("getContextInfo", HandleGetContextInfo);
  register_channel("clearContext", HandleClearContext);
  register_channel("setSystemPromptLength", HandleSetSystemPromptLength);
  register_channel("registerCustomTemplate", HandleRegisterCustomTemplate);
  register_channel("unregisterCustomTemplate", HandleUnregisterCustomTemplate);
  register_channel("detectGpu", HandleDetectGpu);

  g_flutter_api_on_token = fl_basic_message_channel_new(
      messenger, (std::string(kChannelPrefix) + "LlamaFlutterApi.onToken").c_str(),
      FL_MESSAGE_CODEC(codec));
  g_flutter_api_on_done = fl_basic_message_channel_new(
      messenger, (std::string(kChannelPrefix) + "LlamaFlutterApi.onDone").c_str(),
      FL_MESSAGE_CODEC(codec));
  g_flutter_api_on_error = fl_basic_message_channel_new(
      messenger, (std::string(kChannelPrefix) + "LlamaFlutterApi.onError").c_str(),
      FL_MESSAGE_CODEC(codec));
  g_flutter_api_on_load_progress = fl_basic_message_channel_new(
      messenger,
      (std::string(kChannelPrefix) + "LlamaFlutterApi.onLoadProgress").c_str(),
      FL_MESSAGE_CODEC(codec));

  g_object_unref(plugin);
}
