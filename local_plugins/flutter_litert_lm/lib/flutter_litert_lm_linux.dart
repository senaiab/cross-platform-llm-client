import 'package:flutter_litert_lm/flutter_litert_lm_platform_interface.dart';

class FlutterLitertLmLinux extends FlutterLitertLmPlatform {
  static void registerWith() {
    // No-op stub for non-Android platforms
  }

  @override
  Future<String> createEngine(Map<String, dynamic> config) async {
    throw UnsupportedError('LiteRT-LM is not supported on this platform.');
  }

  @override
  Future<void> disposeEngine(String engineId) async {}

  @override
  Future<String> createConversation(
    String engineId,
    Map<String, dynamic>? config,
  ) async {
    throw UnsupportedError('LiteRT-LM is not supported on this platform.');
  }

  @override
  Future<void> disposeConversation(String conversationId) async {}

  @override
  Future<Map<String, dynamic>> sendMessage(
    String conversationId,
    List<Map<String, dynamic>> contents,
    Map<String, Object>? extraContext,
  ) async {
    throw UnsupportedError('LiteRT-LM is not supported on this platform.');
  }

  @override
  Stream<Map<String, dynamic>> sendMessageStream(
    String conversationId,
    List<Map<String, dynamic>> contents,
    Map<String, Object>? extraContext,
  ) {
    throw UnsupportedError('LiteRT-LM is not supported on this platform.');
  }

  @override
  Future<int> countTokens(String engineId, String text) async {
    throw UnsupportedError('LiteRT-LM is not supported on this platform.');
  }
}
