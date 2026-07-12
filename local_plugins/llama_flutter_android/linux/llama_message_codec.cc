#include "llama_message_codec.h"

struct _LlamaMessageCodec {
  FlStandardMessageCodec parent_instance;
};

G_DEFINE_TYPE(LlamaMessageCodec, llama_message_codec,
              fl_standard_message_codec_get_type())

static gboolean llama_message_codec_write_value(FlStandardMessageCodec* codec,
                                                  GByteArray* buffer,
                                                  FlValue* value,
                                                  GError** error) {
  if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_CUSTOM) {
    int type = fl_value_get_custom_type(value);
    if (type == LLAMA_CODEC_TYPE_CONTEXT_INFO ||
        type == LLAMA_CODEC_TYPE_GPU_INFO) {
      guint8 tag = static_cast<guint8>(type);
      g_byte_array_append(buffer, &tag, 1);
      FlValue* fields =
          const_cast<FlValue*>(static_cast<const FlValue*>(
              fl_value_get_custom_value(value)));
      return fl_standard_message_codec_write_value(codec, buffer, fields,
                                                     error);
    }
  }
  return FL_STANDARD_MESSAGE_CODEC_CLASS(llama_message_codec_parent_class)
      ->write_value(codec, buffer, value, error);
}

static FlValue* llama_message_codec_read_value_of_type(
    FlStandardMessageCodec* codec, GBytes* buffer, size_t* offset, int type,
    GError** error) {
  if (type == LLAMA_CODEC_TYPE_MODEL_CONFIG ||
      type == LLAMA_CODEC_TYPE_CHAT_MESSAGE ||
      type == LLAMA_CODEC_TYPE_GENERATE_REQUEST ||
      type == LLAMA_CODEC_TYPE_CHAT_REQUEST) {
    FlValue* fields =
        fl_standard_message_codec_read_value(codec, buffer, offset, error);
    if (fields == nullptr) return nullptr;
    return llama_codec_wrap_custom(type, fields);
  }
  return FL_STANDARD_MESSAGE_CODEC_CLASS(llama_message_codec_parent_class)
      ->read_value_of_type(codec, buffer, offset, type, error);
}

static void llama_message_codec_class_init(LlamaMessageCodecClass* klass) {
  FL_STANDARD_MESSAGE_CODEC_CLASS(klass)->write_value =
      llama_message_codec_write_value;
  FL_STANDARD_MESSAGE_CODEC_CLASS(klass)->read_value_of_type =
      llama_message_codec_read_value_of_type;
}

static void llama_message_codec_init(LlamaMessageCodec* self) {}

LlamaMessageCodec* llama_message_codec_new() {
  return LLAMA_MESSAGE_CODEC(
      g_object_new(llama_message_codec_get_type(), nullptr));
}

FlValue* llama_codec_wrap_custom(int type, FlValue* fields) {
  // fl_value_new_custom takes ownership of the single reference on `fields`
  // via fl_value_unref as its destroy_notify.
  return fl_value_new_custom(type, fields,
                              reinterpret_cast<GDestroyNotify>(fl_value_unref));
}
