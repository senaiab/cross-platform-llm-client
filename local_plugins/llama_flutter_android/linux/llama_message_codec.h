#ifndef LLAMA_MESSAGE_CODEC_H_
#define LLAMA_MESSAGE_CODEC_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

// Pigeon custom type tags, matching the generated Dart/Kotlin codec in
// lib/src/llama_api.dart (LlamaHostApiPigeonCodec). Only used to WRITE
// ContextInfo/GpuInfo (native -> Dart) and READ ModelConfig/ChatMessage/
// GenerateRequest/ChatRequest (Dart -> native); this plugin never needs to
// write the request types or read the response types.
#define LLAMA_CODEC_TYPE_MODEL_CONFIG 129
#define LLAMA_CODEC_TYPE_CHAT_MESSAGE 130
#define LLAMA_CODEC_TYPE_GENERATE_REQUEST 131
#define LLAMA_CODEC_TYPE_CHAT_REQUEST 132
#define LLAMA_CODEC_TYPE_CONTEXT_INFO 133
#define LLAMA_CODEC_TYPE_GPU_INFO 134

G_DECLARE_FINAL_TYPE(LlamaMessageCodec,
                      llama_message_codec,
                      LLAMA,
                      MESSAGE_CODEC,
                      FlStandardMessageCodec)

LlamaMessageCodec* llama_message_codec_new();

// Wraps a plain FL_VALUE_TYPE_LIST of fields as a tagged custom value so the
// Dart-side Pigeon codec decodes it into the matching typed class.
FlValue* llama_codec_wrap_custom(int type, FlValue* fields);

G_END_DECLS

#endif  // LLAMA_MESSAGE_CODEC_H_
