import 'dart:io';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'app_log_service.dart';

/// TTS + wake word service wrapping the Kotlin VoiceBridge.
class VoiceService extends GetxService {
  static const _method = MethodChannel('com.orailnoor.privatelm/voice');
  static const _events = EventChannel('com.orailnoor.privatelm/voice_events');

  final ttsEnabled = false.obs;
  final wakeWordEnabled = false.obs;
  final isSpeaking = false.obs;
  final wakeWordActive = false.obs;

  /// Called when wake word is detected — set by chat controller
  void Function()? onWakeWordDetected;

  Future<VoiceService> init() async {
    if (!Platform.isAndroid) return this;
    try {
      await _method.invokeMethod('initTts');
      _events.receiveBroadcastStream().listen((event) {
        if (event is Map && event['event'] == 'wakeWordDetected') {
          log('Wake word detected');
          onWakeWordDetected?.call();
        }
      });
    } catch (e) {
      log('VoiceService init error: $e');
    }
    return this;
  }

  Future<void> speak(String text) async {
    if (!Platform.isAndroid || !ttsEnabled.value || text.trim().isEmpty) return;
    // Strip markdown for cleaner speech
    final clean = text
        .replaceAll(RegExp(r'\*\*?|__?|~~|`{1,3}|#{1,6}\s?'), '')
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
        .replaceAll(RegExp(r'\n{2,}'), '. ')
        .replaceAll('\n', ' ')
        .trim();
    if (clean.isEmpty) return;
    isSpeaking.value = true;
    try {
      await _method.invokeMethod('speak', {'text': clean});
    } on PlatformException catch (e) {
      log('TTS speak error: ${e.message}');
    } finally {
      isSpeaking.value = false;
    }
  }

  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    isSpeaking.value = false;
    try {
      await _method.invokeMethod('stopSpeaking');
    } catch (_) {}
  }

  Future<void> startWakeWord() async {
    if (!Platform.isAndroid || !wakeWordEnabled.value) return;
    try {
      final ok = await _method.invokeMethod<bool>('startWakeWord') ?? false;
      wakeWordActive.value = ok;
      if (ok) log('Wake word listening started');
    } on PlatformException catch (e) {
      log('Wake word start error: ${e.message}');
    }
  }

  Future<void> stopWakeWord() async {
    if (!Platform.isAndroid) return;
    try {
      await _method.invokeMethod('stopWakeWord');
      wakeWordActive.value = false;
    } catch (_) {}
  }

  void log(String msg) {
    if (Get.isRegistered<AppLogService>()) {
      Get.find<AppLogService>().info('[Voice] $msg');
    }
  }
}
