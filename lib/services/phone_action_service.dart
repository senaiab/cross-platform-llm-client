import 'dart:io';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'app_log_service.dart';

/// Dart-side wrapper for the OpenDroid phone automation method channel.
/// Channel: com.orailnoor.privatelm/phone_actions
class PhoneActionService extends GetxService {
  static const _channel = MethodChannel('com.orailnoor.privatelm/phone_actions');

  final isAccessibilityEnabled = false.obs;

  Future<PhoneActionService> init() async {
    if (!Platform.isAndroid) return this;
    await refreshAccessibilityStatus();
    return this;
  }

  Future<void> refreshAccessibilityStatus() async {
    try {
      final enabled = await _channel.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
      isAccessibilityEnabled.value = enabled;
    } catch (_) {
      isAccessibilityEnabled.value = false;
    }
  }

  Future<void> openAccessibilitySettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('openAccessibilitySettings');
  }

  /// Send a WhatsApp message to [contact] (phone number or name).
  /// Returns null on success, error string on failure.
  Future<String?> sendWhatsApp(String contact, String message) async {
    if (!Platform.isAndroid) return 'Android only';
    await refreshAccessibilityStatus();
    if (!isAccessibilityEnabled.value) {
      return 'Accessibility service not enabled. Go to Settings → Accessibility → PrivateLM Agent and enable it.';
    }
    try {
      final result = await _channel.invokeMethod<Map>('sendWhatsApp', {
        'contact': contact,
        'message': message,
      });
      final success = result?['success'] as bool? ?? false;
      return success ? null : 'WhatsApp send failed — make sure WhatsApp is installed and the chat is open.';
    } on PlatformException catch (e) {
      return e.message ?? e.code;
    }
  }

  /// Send an SMS to [to] (phone number).
  Future<String?> sendSms(String to, String message) async {
    if (!Platform.isAndroid) return 'Android only';
    try {
      final result = await _channel.invokeMethod<Map>('sendSms', {
        'to': to,
        'message': message,
      });
      final success = result?['success'] as bool? ?? false;
      return success ? null : 'SMS send failed.';
    } on PlatformException catch (e) {
      return e.message ?? e.code;
    }
  }

  /// Make a phone call to [to] (phone number).
  Future<String?> makeCall(String to) async {
    if (!Platform.isAndroid) return 'Android only';
    try {
      final result = await _channel.invokeMethod<Map>('makeCall', {'to': to});
      final success = result?['success'] as bool? ?? false;
      return success ? null : 'Call failed.';
    } on PlatformException catch (e) {
      return e.message ?? e.code;
    }
  }

  /// Get all visible text from the current screen.
  Future<String> getScreenText() async {
    if (!Platform.isAndroid) return '';
    await refreshAccessibilityStatus();
    if (!isAccessibilityEnabled.value) {
      return 'ERROR: Accessibility service not enabled.';
    }
    try {
      return await _channel.invokeMethod<String>('getScreenText') ?? '';
    } on PlatformException catch (e) {
      return 'ERROR: ${e.message ?? e.code}';
    }
  }

  /// Click at screen coordinates [x], [y].
  Future<bool> clickOnScreen(double x, double y) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('clickOnScreen', {'x': x, 'y': y}) ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Find a UI element by visible text and click it.
  Future<bool> findAndClick(String text) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('findAndClick', {'text': text}) ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Find an editable field by label and type [content] into it.
  Future<bool> findAndType(String label, String content) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('findAndType', {
        'text': label,
        'content': content,
      }) ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Take a screenshot and return it as a base64-encoded JPEG string.
  Future<String?> takeScreenshot() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('takeScreenshot');
    } on PlatformException catch (_) {
      return null;
    }
  }

  /// Launch an app by its package name.
  Future<String?> openApp(String packageName) async {
    if (!Platform.isAndroid) return 'Android only';
    try {
      await _channel.invokeMethod('openApp', {'packageName': packageName});
      return null;
    } on PlatformException catch (e) {
      return e.message ?? e.code;
    }
  }

  void log(String msg) {
    if (Get.isRegistered<AppLogService>()) {
      Get.find<AppLogService>().info('[PhoneAction] $msg');
    }
  }
}
