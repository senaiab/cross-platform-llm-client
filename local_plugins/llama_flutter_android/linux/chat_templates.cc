#include "chat_templates.h"

#include <algorithm>
#include <regex>
#include <set>
#include <sstream>

namespace {

std::string ToLower(std::string s) {
  std::transform(s.begin(), s.end(), s.begin(),
                  [](unsigned char c) { return std::tolower(c); });
  return s;
}

bool Contains(const std::string& haystack, const std::string& needle) {
  return haystack.find(needle) != std::string::npos;
}

std::string Trim(const std::string& s) {
  size_t start = s.find_first_not_of(" \t\n\r");
  if (start == std::string::npos) return "";
  size_t end = s.find_last_not_of(" \t\n\r");
  return s.substr(start, end - start + 1);
}

const TemplateChatMessage* FindFirst(
    const std::vector<TemplateChatMessage>& messages, const std::string& role) {
  for (const auto& m : messages) {
    if (m.role == role) return &m;
  }
  return nullptr;
}

// ---- Built-in template formatters (ported from ChatTemplates.kt) ----

std::string FormatChatMl(const std::vector<TemplateChatMessage>& messages) {
  std::ostringstream out;
  for (const auto& m : messages) {
    out << "<|im_start|>" << m.role << "\n" << m.content << "<|im_end|>\n";
  }
  out << "<|im_start|>assistant\n";
  return out.str();
}

std::string FormatLlama3(const std::vector<TemplateChatMessage>& messages) {
  std::ostringstream out;
  out << "<|begin_of_text|>";
  for (const auto& m : messages) {
    out << "<|start_header_id|>" << m.role << "<|end_header_id|>\n\n"
        << Trim(m.content) << "<|eot_id|>";
  }
  out << "<|start_header_id|>assistant<|end_header_id|>\n\n";
  return out.str();
}

std::string FormatLlama2(const std::vector<TemplateChatMessage>& messages) {
  std::ostringstream out;
  out << "<s>";
  bool has_system = false;
  std::string system_message;
  for (const auto& m : messages) {
    if (m.role == "system") {
      system_message = Trim(m.content);
      has_system = true;
      break;
    }
  }
  bool is_first_user = true;
  for (const auto& m : messages) {
    if (m.role == "system") continue;
    if (m.role == "user") {
      if (!is_first_user) out << "</s><s>";
      out << "[INST] ";
      if (is_first_user && has_system) {
        out << "<<SYS>>\n" << system_message << "\n<</SYS>>\n\n";
      }
      out << Trim(m.content) << " [/INST]";
      is_first_user = false;
    } else if (m.role == "assistant") {
      out << " " << Trim(m.content);
    }
  }
  return out.str();
}

// Note: Alpaca/Vicuna/Phi below intentionally emit literal backslash-n
// ("\\n") rather than real newlines, matching a quirk in the upstream
// Kotlin ChatTemplates.kt (Kotlin `\\n` in a string literal is a literal
// two-character escape, not `\n`). Preserved here for output parity with
// the Android build.

std::string FormatAlpaca(const std::vector<TemplateChatMessage>& messages) {
  std::ostringstream out;
  const auto* sys = FindFirst(messages, "system");
  std::string system_message =
      sys ? sys->content
          : "Below is an instruction that describes a task. Write a "
            "response that appropriately completes the request.";
  out << system_message << "\\n\\n";
  for (const auto& m : messages) {
    if (m.role == "user") {
      out << "### Instruction:\\n" << m.content << "\\n\\n";
    } else if (m.role == "assistant") {
      out << "### Response:\\n" << m.content << "\\n\\n";
    }
  }
  out << "### Response:\\n";
  return out.str();
}

std::string FormatVicuna(const std::vector<TemplateChatMessage>& messages) {
  std::ostringstream out;
  const auto* sys = FindFirst(messages, "system");
  std::string system_message =
      sys ? sys->content
          : "A chat between a curious user and an artificial intelligence "
            "assistant. The assistant gives helpful, detailed, and polite "
            "answers to the user's questions.";
  out << system_message << "\\n\\n";
  for (const auto& m : messages) {
    if (m.role == "user") {
      out << "USER: " << m.content << "\\n";
    } else if (m.role == "assistant") {
      out << "ASSISTANT: " << m.content << "\\n";
    }
  }
  out << "ASSISTANT:";
  return out.str();
}

std::string FormatPhi(const std::vector<TemplateChatMessage>& messages) {
  std::ostringstream out;
  for (const auto& m : messages) {
    if (m.role == "system") {
      out << "<|system|>\\n" << m.content << "<|end|>\\n";
    } else if (m.role == "user") {
      out << "<|user|>\\n" << m.content << "<|end|>\\n";
    } else if (m.role == "assistant") {
      out << "<|assistant|>\\n" << m.content << "<|end|>\\n";
    }
  }
  out << "<|assistant|>\\n";
  return out.str();
}

std::string FormatGemma2(const std::vector<TemplateChatMessage>& messages) {
  std::ostringstream out;
  out << "<bos>";
  bool has_system = false;
  std::string system_content;
  for (size_t index = 0; index < messages.size(); index++) {
    const auto& m = messages[index];
    if (m.role == "system") {
      system_content = m.content;
      has_system = true;
      continue;
    }
    if (m.role == "user") {
      out << "<start_of_turn>user\n";
      if (has_system && index <= 1) {
        out << system_content << "\n\n";
        has_system = false;
      }
      out << m.content << "<end_of_turn>\n";
    } else if (m.role == "assistant") {
      out << "<start_of_turn>model\n" << m.content << "<end_of_turn>";
      if (index < messages.size() - 1) out << "<eos>";
      out << "\n";
    }
  }
  out << "<start_of_turn>model\n";
  return out.str();
}

std::string FormatGemma3(const std::vector<TemplateChatMessage>& messages) {
  std::ostringstream out;
  out << "<bos>";
  bool has_system = false;
  std::string system_content;
  for (const auto& m : messages) {
    if (m.role == "system") {
      system_content = m.content;
      has_system = true;
      continue;
    }
    if (m.role == "user") {
      out << "<start_of_turn>user\n";
      if (has_system) {
        out << system_content << "\n\n";
        has_system = false;
      }
      out << m.content << "<end_of_turn>\n";
    } else if (m.role == "assistant") {
      out << "<start_of_turn>model\n" << m.content << "<end_of_turn>\n";
    }
  }
  out << "<start_of_turn>model\n";
  return out.str();
}

std::string StripReasoningBlocks(const std::string& content) {
  static const std::regex kThinkBlock("<think>[\\s\\S]*?</think>");
  return Trim(std::regex_replace(content, kThinkBlock, ""));
}

std::string FormatQwQ(const std::vector<TemplateChatMessage>& messages) {
  std::ostringstream out;
  for (const auto& m : messages) {
    std::string content =
        m.role == "assistant" ? StripReasoningBlocks(m.content) : m.content;
    if (!Trim(content).empty() || m.role != "assistant") {
      out << "<|im_start|>" << m.role << "\n" << content << "<|im_end|>\n";
    }
  }
  out << "<|im_start|>assistant\n";
  return out.str();
}

std::string FormatMistral(const std::vector<TemplateChatMessage>& messages) {
  std::ostringstream out;
  out << "<s>";
  const auto* sys = FindFirst(messages, "system");
  bool has_system = sys != nullptr;
  std::string system_message = has_system ? Trim(sys->content) : "";
  bool is_first = true;
  for (const auto& m : messages) {
    if (m.role == "system") continue;
    if (m.role == "user") {
      if (!is_first) out << "</s>";
      out << "[INST] ";
      if (is_first && has_system) out << system_message << "\n\n";
      out << Trim(m.content) << " [/INST]";
      is_first = false;
    } else if (m.role == "assistant") {
      out << Trim(m.content);
    }
  }
  return out.str();
}

// U+FF5C (fullwidth vertical line) and U+2581 (lower one eighth block) are
// used verbatim as UTF-8 text below, matching DeepSeek's special tokens.
const char kBOS[] = "<｜begin▁of▁sentence｜>";
const char kEOS[] = "<｜end▁of▁sentence｜>";
const char kUserTok[] = "<｜User｜>";
const char kAssistantTok[] = "<｜Assistant｜>";

std::string FormatDeepSeekCoder(const std::vector<TemplateChatMessage>& messages) {
  std::ostringstream out;
  out << kBOS;
  const auto* sys = FindFirst(messages, "system");
  if (sys) out << Trim(sys->content) << " ";
  bool is_first = true;
  for (const auto& m : messages) {
    if (m.role == "system") continue;
    if (m.role == "user") {
      if (!is_first) out << kEOS;
      out << "User: " << Trim(m.content) << "\n";
      is_first = false;
    } else if (m.role == "assistant") {
      out << "Assistant: " << Trim(m.content) << "\n";
    }
  }
  out << "Assistant: ";
  return out.str();
}

std::string FormatDeepSeekR1(const std::vector<TemplateChatMessage>& messages) {
  std::ostringstream out;
  out << kBOS;
  const auto* sys = FindFirst(messages, "system");
  if (sys) out << Trim(sys->content);
  for (const auto& m : messages) {
    if (m.role == "system") continue;
    if (m.role == "user") {
      out << kUserTok << Trim(m.content);
    } else if (m.role == "assistant") {
      out << kAssistantTok << "</think>" << Trim(m.content);
    }
  }
  out << kAssistantTok << "</think>";
  return out.str();
}

std::string ReplaceAll(std::string s, const std::string& from,
                        const std::string& to) {
  size_t pos = 0;
  while ((pos = s.find(from, pos)) != std::string::npos) {
    s.replace(pos, from.size(), to);
    pos += to.size();
  }
  return s;
}

std::string FormatRaw(const std::vector<TemplateChatMessage>& messages,
                       const std::string& content) {
  std::ostringstream out;
  for (const auto& m : messages) {
    if (m.role == "system") {
      out << ReplaceAll(content, "{system}", m.content);
    } else if (m.role == "user") {
      out << ReplaceAll(content, "{user}", m.content);
    } else if (m.role == "assistant") {
      out << ReplaceAll(content, "{assistant}", m.content);
    } else {
      out << ReplaceAll(content, "{user}", m.content);
    }
  }
  return out.str();
}

}  // namespace

ChatTemplateManager& ChatTemplateManager::Instance() {
  static ChatTemplateManager instance;
  return instance;
}

void ChatTemplateManager::RegisterCustomTemplate(const std::string& name,
                                                  const std::string& content) {
  custom_templates_[ToLower(name)] = content;
}

bool ChatTemplateManager::UnregisterCustomTemplate(const std::string& name) {
  return custom_templates_.erase(ToLower(name)) > 0;
}

std::vector<std::string> ChatTemplateManager::GetSupportedTemplates() const {
  static const std::vector<std::string> kBuiltIn = {
      "chatml",   "qwen",     "qwen2",     "qwen2.5",  "command-r",
      "llama3",   "llama-3",  "llama3.1",  "llama3.3", "llama2",
      "llama-2",  "qwq",      "qwq-32b",   "deepseek-r1", "deepseek-v3",
      "mistral",  "mixtral",  "deepseek-coder", "alpaca", "vicuna",
      "phi",      "phi-3",    "gemma",     "gemma2",   "gemma-2",
      "gemma3",   "gemma-3"};
  std::set<std::string> all(kBuiltIn.begin(), kBuiltIn.end());
  for (const auto& kv : custom_templates_) all.insert(kv.first);
  return std::vector<std::string>(all.begin(), all.end());
}

std::string ChatTemplateManager::FormatWithBuiltin(
    const std::string& name,
    const std::vector<TemplateChatMessage>& messages) const {
  if (name == "chatml" || name == "qwen" || name == "qwen2" ||
      name == "qwen2.5" || name == "command-r") {
    return FormatChatMl(messages);
  }
  if (name == "llama3" || name == "llama-3" || name == "llama3.1" ||
      name == "llama3.3") {
    return FormatLlama3(messages);
  }
  if (name == "llama2" || name == "llama-2") return FormatLlama2(messages);
  if (name == "qwq" || name == "qwq-32b") return FormatQwQ(messages);
  if (name == "deepseek-r1" || name == "deepseek-v3") {
    return FormatDeepSeekR1(messages);
  }
  if (name == "mistral" || name == "mixtral") return FormatMistral(messages);
  if (name == "deepseek-coder") return FormatDeepSeekCoder(messages);
  if (name == "alpaca") return FormatAlpaca(messages);
  if (name == "vicuna") return FormatVicuna(messages);
  if (name == "phi" || name == "phi-3") return FormatPhi(messages);
  if (name == "gemma" || name == "gemma2" || name == "gemma-2") {
    return FormatGemma2(messages);
  }
  if (name == "gemma3" || name == "gemma-3") return FormatGemma3(messages);
  return FormatChatMl(messages);
}

std::string ChatTemplateManager::DetectTemplateName(
    const std::string& model_path) const {
  std::string p = ToLower(model_path);

  if (Contains(p, "qwq")) return "qwq";
  if (Contains(p, "deepseek-r1") || Contains(p, "deepseek_r1")) return "deepseek-r1";
  if (Contains(p, "deepseek-coder") || Contains(p, "deepseek_coder")) return "deepseek-coder";
  if (Contains(p, "deepseek") && (Contains(p, "v3") || Contains(p, "v3.1"))) return "deepseek-r1";
  if (Contains(p, "qwen2.5") || Contains(p, "qwen2_5")) return "qwen2.5";
  if (Contains(p, "qwen2")) return "qwen2";
  if (Contains(p, "qwen")) return "qwen";
  if (Contains(p, "llama-3") || Contains(p, "llama3") || Contains(p, "llama_3")) return "llama3";
  if (Contains(p, "llama-2") || Contains(p, "llama2") || Contains(p, "llama_2")) return "llama2";
  if (Contains(p, "mixtral")) return "mixtral";
  if (Contains(p, "mistral")) return "mistral";
  if (Contains(p, "command-r") || Contains(p, "command_r")) return "command-r";
  if (Contains(p, "phi-3") || Contains(p, "phi3")) return "phi-3";
  if (Contains(p, "phi")) return "phi";
  if (Contains(p, "gemma-3") || Contains(p, "gemma3") || Contains(p, "gemma_3")) return "gemma3";
  if (Contains(p, "gemma-2") || Contains(p, "gemma2") || Contains(p, "gemma_2")) return "gemma2";
  if (Contains(p, "gemma")) return "gemma2";
  if (Contains(p, "alpaca")) return "alpaca";
  if (Contains(p, "vicuna")) return "vicuna";
  return "chatml";
}

std::string ChatTemplateManager::FormatMessages(
    const std::vector<TemplateChatMessage>& messages,
    const std::string& template_name, const std::string& model_path) const {
  if (!template_name.empty()) {
    std::string key = ToLower(template_name);
    auto custom_it = custom_templates_.find(key);
    if (custom_it != custom_templates_.end()) {
      return FormatRaw(messages, custom_it->second);
    }
    return FormatWithBuiltin(key, messages);
  }
  if (!model_path.empty()) {
    return FormatWithBuiltin(DetectTemplateName(model_path), messages);
  }
  return FormatChatMl(messages);
}
