#ifndef CHAT_TEMPLATES_H_
#define CHAT_TEMPLATES_H_

#include <map>
#include <string>
#include <vector>

// Ported from ChatTemplates.kt — chat template formatting for llama.cpp
// text completion. Kept behavior-identical to the Android implementation
// so a given model produces the same prompt on both platforms.
struct TemplateChatMessage {
  std::string role;  // "system", "user", or "assistant"
  std::string content;
};

class ChatTemplateManager {
 public:
  static ChatTemplateManager& Instance();

  // Registers/unregisters a raw custom template with {system}/{user}/
  // {assistant} placeholders.
  void RegisterCustomTemplate(const std::string& name,
                               const std::string& content);
  bool UnregisterCustomTemplate(const std::string& name);

  std::vector<std::string> GetSupportedTemplates() const;

  // Formats messages using the explicit template name if given and known,
  // otherwise falls back to filename-based auto-detection against
  // model_path, otherwise ChatML.
  std::string FormatMessages(const std::vector<TemplateChatMessage>& messages,
                              const std::string& template_name,
                              const std::string& model_path) const;

 private:
  ChatTemplateManager() = default;

  std::string DetectTemplateName(const std::string& model_path) const;
  std::string FormatWithBuiltin(const std::string& template_name,
                                 const std::vector<TemplateChatMessage>& messages) const;

  std::map<std::string, std::string> custom_templates_;  // name -> raw content
};

#endif  // CHAT_TEMPLATES_H_
