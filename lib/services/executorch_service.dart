import 'dart:io';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'app_log_service.dart';

class ExecuTorchService extends GetxService {
  static const _channel = MethodChannel('com.orailnoor.privatelm/executorch');

  final isLoaded = false.obs;
  final isGenerating = false.obs;
  final tokensPerSecond = 0.0.obs;
  final loadedModelPath = ''.obs;
  final htpArch = ''.obs;

  void Function(String token)? _onToken;

  Future<ExecuTorchService> init() async {
    if (!Platform.isAndroid) return this;
    _channel.setMethodCallHandler(_handleMethodCall);
    try {
      final info = await _channel.invokeMethod<Map>('deviceInfo');
      htpArch.value = info?['htpArch']?.toString() ?? '';
      final qnnLoaded = info?['qnnBackendLoaded'] as bool? ?? false;
      final qnnErr = info?['qnnBackendError']?.toString() ?? '';
      log('ExecuTorch device: arch=${htpArch.value}, QNN=${info?['systemQnnVersion'] ?? 'unknown'}, backendLoaded=$qnnLoaded${qnnErr.isNotEmpty ? ', backendErr=$qnnErr' : ''}');
    } catch (e) {
      log('ExecuTorch deviceInfo failed: $e');
    }
    return this;
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onToken') {
      _onToken?.call(call.arguments as String);
    }
  }

  /// Returns null on success, error string on failure.
  Future<String?> loadModel(String modelPath, String tokenizerPath) async {
    if (!Platform.isAndroid) return 'ExecuTorch is Android-only';
    try {
      final ok = await _channel.invokeMethod<bool>('load', {
        'modelPath': modelPath,
        'tokenizerPath': tokenizerPath,
        'temperature': 0.7,
      });
      if (ok == true) {
        isLoaded.value = true;
        loadedModelPath.value = modelPath;
        log('ExecuTorch loaded: $modelPath');
        return null;
      }
      return 'ExecuTorch load returned false';
    } on PlatformException catch (e) {
      return e.message ?? e.code;
    }
  }

  Future<String> generate(
    String prompt, {
    int maxTokens = 2048,
    void Function(String token)? onToken,
  }) async {
    if (!isLoaded.value) return 'ERROR: No PTE model loaded';
    isGenerating.value = true;
    final buffer = StringBuffer();
    _onToken = (token) {
      buffer.write(token);
      onToken?.call(token);
    };
    try {
      final result = await _channel.invokeMethod<Map>('generate', {
        'prompt': prompt,
        'maxTokens': maxTokens,
      });
      tokensPerSecond.value = (result?['tps'] as num?)?.toDouble() ?? 0.0;
      return buffer.toString();
    } on PlatformException catch (e) {
      return 'ERROR: ${e.message ?? e.code}';
    } finally {
      _onToken = null;
      isGenerating.value = false;
    }
  }

  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    runCatching(() => _channel.invokeMethod('stop'));
    isGenerating.value = false;
  }

  Future<bool> hasAllFilesAccess() async {
    if (!Platform.isAndroid) return true;
    return await _channel.invokeMethod<bool>('hasAllFilesAccess') ?? true;
  }

  Future<void> openAllFilesSettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('openAllFilesSettings');
  }

  /// Copies [src] (external storage path) to [dst] (internal path) via Kotlin.
  /// Returns null on success, 'PERMISSION_REQUIRED' if All Files Access is needed,
  /// or another error string on failure.
  /// Returns the app-internal directory for ExecuTorch model files (filesDir/et_models).
  /// C++ can always open paths here regardless of external storage permissions.
  Future<String> getEtModelsDir() async {
    if (!Platform.isAndroid) return '/tmp';
    return await _channel.invokeMethod<String>('getEtModelsDir') ?? '';
  }

  Future<String?> copyTokenizer(String src, String dst) async {
    if (!Platform.isAndroid) return null;
    try {
      await _channel.invokeMethod<void>('copyTokenizer', {'src': src, 'dst': dst});
      return null;
    } on PlatformException catch (e) {
      return e.code == 'PERMISSION_REQUIRED' ? 'PERMISSION_REQUIRED' : (e.message ?? e.code);
    }
  }

  Future<void> unload() async {
    if (!Platform.isAndroid) return;
    runCatching(() => _channel.invokeMethod('unload'));
    isLoaded.value = false;
    loadedModelPath.value = '';
    tokensPerSecond.value = 0.0;
  }

  /// Finds the tokenizer alongside a .pte file.
  /// Checks <stem>.bin, tokenizer.bin, tokenizer.model in same dir,
  /// then falls back to common external storage locations.
  static String? findTokenizer(String ptePath) {
    final dir = File(ptePath).parent;
    final stem = File(ptePath).uri.pathSegments.last.replaceAll('.pte', '');
    const externalDirs = [
      '/storage/emulated/0/LLM-MODELS',
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Documents',
    ];
    final candidates = [
      // Model-specific files alongside PTE (these are deliberately placed, trust them)
      File('${dir.path}/$stem.bin'),
      File('${dir.path}/$stem-tokenizer.bin'),
      // External storage dirs preferred over generic sibling tokenizer.bin so that
      // an updated external tokenizer triggers a fresh copy rather than reusing a
      // potentially stale internal cache named tokenizer.bin.
      for (final d in externalDirs) ...[
        File('$d/$stem.bin'),
        File('$d/$stem-tokenizer.bin'),
        File('$d/tokenizer.bin'),
        File('$d/tokenizer.model'),
      ],
      // Generic sibling files last (may be our own internal cache copy)
      File('${dir.path}/tokenizer.bin'),
      File('${dir.path}/tokenizer.model'),
    ];
    return candidates.firstWhereOrNull((f) => f.existsSync())?.path;
  }

  void log(String msg) {
    if (Get.isRegistered<AppLogService>()) {
      Get.find<AppLogService>().info('[ExecuTorch] $msg');
    }
  }
}

void runCatching(void Function() fn) {
  try { fn(); } catch (_) {}
}
