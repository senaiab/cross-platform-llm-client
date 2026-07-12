import 'dart:convert';
import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../controllers/chat_controller.dart';
import '../controllers/settings_controller.dart';
import '../ffi/sd_ffi_bindings.dart';
import 'app_log_service.dart';
import 'device_info_service.dart';
import 'inference_service.dart';
import 'local_image_service.dart';

class CrashReportingService extends GetxService {
  bool _enabled = false;
  bool _reporting = false;
  PackageInfo? _packageInfo;
  AndroidDeviceInfo? _androidInfo;
  Directory? _reportsDir;

  static const int _maxReports = 50;

  bool get isEnabled => _enabled;

  Future<CrashReportingService> init() async {
    try {
      _packageInfo = await PackageInfo.fromPlatform();
      if (!kIsWeb && Platform.isAndroid) {
        _androidInfo = await DeviceInfoPlugin().androidInfo;
      }
      final base = await getApplicationDocumentsDirectory();
      _reportsDir = Directory('${base.path}/crash_reports');
      await _reportsDir!.create(recursive: true);
      _enabled = true;
      log('Crash reporting initialized (local)');
    } catch (e) {
      _enabled = false;
      print('[CrashReporting] Disabled: $e');
    }
    return this;
  }

  Future<void> recordFlutterFatal(FlutterErrorDetails details) async {
    await _write(
      type: 'flutter_fatal',
      error: details.exceptionAsString(),
      stack: details.stack?.toString() ?? '',
    );
  }

  Future<void> recordFatal(Object error, StackTrace stack,
      {String reason = 'fatal'}) async {
    await _write(type: reason, error: error.toString(), stack: stack.toString());
  }

  Future<void> recordNonFatal(
    Object error, {
    StackTrace? stack,
    String reason = 'nonfatal',
    Map<String, Object?> extra = const {},
  }) async {
    if (!_enabled || _reporting) return;
    _reporting = true;
    try {
      await _write(
        type: reason,
        error: error.toString(),
        stack: (stack ?? StackTrace.current).toString(),
        extra: extra,
      );
    } catch (e) {
      print('[CrashReporting] Write failed: $e');
    } finally {
      _reporting = false;
    }
  }

  void log(String message) {
    if (!_enabled) return;
    // Local mode: log entries are already captured by AppLogService.
  }

  Future<void> updateContext({
    String reason = 'context',
    Map<String, Object?> extra = const {},
  }) async {
    // No-op in local mode — context is embedded in each report.
  }

  Future<void> _write({
    required String type,
    required String error,
    required String stack,
    Map<String, Object?> extra = const {},
  }) async {
    if (!_enabled) return;
    final dir = _reportsDir;
    if (dir == null) return;

    final now = DateTime.now();
    final report = {
      'timestamp': now.toIso8601String(),
      'type': type,
      'error': _trim(error, 2000),
      'stack': _trim(stack, 4000),
      'package': _packageKeys(),
      'device': _deviceKeys(),
      'settings': _settingsKeys(),
      'text_model': _textModelKeys(),
      'image_model': _imageModelKeys(),
      'generation': _generationKeys(),
      'recent_logs': _importantLogs(),
      ...extra.map((k, v) => MapEntry(k, v?.toString() ?? '')),
    };

    final filename =
        '${now.toIso8601String().replaceAll(':', '-').replaceAll('.', '-')}_$type.json';
    final file = File('${dir.path}/$filename');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    await _pruneOldReports(dir);
  }

  Future<void> _pruneOldReports(Directory dir) async {
    try {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      if (files.length > _maxReports) {
        for (final f in files.take(files.length - _maxReports)) {
          await f.delete();
        }
      }
    } catch (_) {}
  }

  Map<String, Object?> _packageKeys() {
    final info = _packageInfo;
    if (info == null) return {};
    return {
      'name': info.appName,
      'package': info.packageName,
      'version': info.version,
      'build': info.buildNumber,
    };
  }

  Map<String, Object?> _deviceKeys() {
    final keys = <String, Object?>{};
    if (!kIsWeb) {
      keys['platform'] = Platform.operatingSystem;
      keys['platform_version'] = Platform.operatingSystemVersion;
    }
    if (Get.isRegistered<DeviceInfoService>()) {
      final device = Get.find<DeviceInfoService>();
      keys.addAll({
        'total_ram_gb': device.totalRamGB.value,
        'available_ram_gb': device.availableRamGB.value,
        'tier': device.deviceTier.value,
        'soc_family': device.socFamily.value.name,
        'soc_hardware': _trim(device.socHardware.value, 120),
        'tensor_soc': device.isTensorSoC.value,
      });
    }
    final android = _androidInfo;
    if (android != null) {
      keys.addAll({
        'manufacturer': android.manufacturer,
        'model': android.model,
        'sdk': android.version.sdkInt,
        'release': android.version.release,
      });
    }
    return keys;
  }

  Map<String, Object?> _settingsKeys() {
    if (!Get.isRegistered<SettingsController>()) return {};
    final s = Get.find<SettingsController>();
    return {
      'inference_mode': s.inferenceMode.value,
      'image_steps': s.imageSteps.value,
      'image_backend': s.imageGenBackend.value.displayName,
    };
  }

  Map<String, Object?> _textModelKeys() {
    if (!Get.isRegistered<InferenceService>()) return {};
    final i = Get.find<InferenceService>();
    return {
      'loaded': i.isModelLoaded.value,
      'name': _safeName(i.loadedModelName.value),
      'runtime': i.loadedModelRuntime.value,
      'gpu': i.isGpuAccelerated.value,
      'gpu_layers': i.gpuLayersUsed.value,
      'context_used': i.contextTokensUsed.value,
      'context_total': i.contextTokensTotal.value,
    };
  }

  Map<String, Object?> _imageModelKeys() {
    if (!Get.isRegistered<LocalImageService>()) return {};
    final img = Get.find<LocalImageService>();
    return {
      'loaded': img.isModelLoaded.value,
      'name': _safeName(img.loadedModelName.value),
      'backend': img.currentBackend.value.displayName,
      'gpu': img.currentBackend.value != Backend.cpu,
      'generating': img.isGenerating.value,
    };
  }

  Map<String, Object?> _generationKeys() {
    if (!Get.isRegistered<ChatController>()) return {};
    final chat = Get.find<ChatController>();
    final start = chat.imageGenStartTime.value;
    return {
      'loading': chat.isLoading.value,
      'streaming': chat.isStreaming.value,
      'image_step': chat.imageGenStep.value,
      'image_total': chat.imageGenTotal.value,
      'elapsed_secs':
          start == null ? 0 : DateTime.now().difference(start).inSeconds,
    };
  }

  String _importantLogs() {
    if (!Get.isRegistered<AppLogService>()) return '';
    return Get.find<AppLogService>()
        .importantEntries
        .take(12)
        .map((e) => e.format())
        .join('\n---\n');
  }

  String _safeName(String value) {
    if (value.trim().isEmpty) return '';
    return _trim(value.replaceAll('\\', '/').split('/').last, 160);
  }

  String _trim(String value, int max) {
    if (value.length <= max) return value;
    return '${value.substring(0, max - 3)}...';
  }
}
