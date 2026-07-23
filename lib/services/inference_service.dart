import 'dart:async';
import 'dart:io';
import 'package:get/get.dart';
import 'hive_service.dart';
import '../core/constants.dart';
import 'device_info_service.dart';
import 'app_log_service.dart';
import 'executorch_service.dart';

// Conditionally import llama_flutter_android — only on Android
import 'inference_android.dart' if (dart.library.html) 'inference_stub.dart'
    as platform;

/// Cross-platform inference service.
/// - Android / iOS: uses llama_flutter_android for local GGUF models
/// - Android: uses flutter_litert_lm for LiteRT-LM models
/// - Web: cloud-only mode (local inference coming soon)
class InferenceService extends GetxService {
  final HiveService _hive = Get.find<HiveService>();

  // ── Observable State ──
  final isModelLoaded = false.obs;
  final isGenerating = false.obs;
  final isLoadingModel = false.obs;
  final isVisionLoaded = false.obs;
  final loadingModelName = ''.obs;
  final loadedModelName = ''.obs;
  final tokenCount = 0.obs;
  final tokensPerSecond = 0.0.obs;
  final contextTokensUsed = 0.obs;
  final contextTokensTotal = 0.obs;
  final modelLoadProgress = 0.0.obs;
  final generationSource = ''.obs;
  final streamingText = ''.obs;
  final gpuName = ''.obs;
  final gpuLayersUsed = 0.obs;
  final isGpuAccelerated = false.obs;
  final loadedModelRuntime = ''.obs;
  final loadedBackend = ''.obs;

  /// Whether the current platform supports local inference.
  bool get supportsLocalInference => platform.supportsLocalInference;

  // Platform-specific engine
  platform.InferenceEngine? _engine;
  String _sessionNativeRuntime = '';

  String get sessionNativeRuntime => _sessionNativeRuntime;

  bool requiresAppRestartForRuntime(String runtime) {
    final normalized = runtime.toLowerCase();
    if (normalized != 'llama' && normalized != 'litert') return false;
    return _sessionNativeRuntime.isNotEmpty &&
        _sessionNativeRuntime != normalized;
  }

  Future<String> loadModel(
    String modelPath, {
    String? modelName,
    String? modelRuntime,
    bool enableLiteRtVision = false,
  }) async {
    if (!supportsLocalInference) {
      return 'ERROR: Local inference is not available on this platform. Use Cloud mode.';
    }
    if (isLoadingModel.value) return 'ERROR: Model is already loading.';

    if (modelPath.toLowerCase().endsWith('.safetensors')) {
      return 'ERROR: Cannot load image generation models (.safetensors) into the local text engine. Native local image generation requires the upcoming stable-diffusion engine update. Use Cloud Stability AI for now.';
    }

    if (modelPath.toLowerCase().endsWith('.pte')) {
      return _loadExecuTorchModel(modelPath, modelName: modelName);
    }

    try {
      final runtime = _runtimeFor(modelPath, modelRuntime);
      final isLiteRt = runtime == 'litert';
      final liteRtMode = _hive.getSetting<String>(
            AppConstants.keyLiteRtPerformanceMode,
            defaultValue: AppConstants.defaultLiteRtPerformanceMode,
          ) ??
          AppConstants.defaultLiteRtPerformanceMode;
      final hadPendingGpuLoad = isLiteRt &&
          (_hive.getSetting<bool>(
                AppConstants.keyLiteRtGpuLoadPending,
                defaultValue: false,
              ) ??
              false);
      if (hadPendingGpuLoad) {
        await _hive.setSetting(AppConstants.keyLiteRtGpuLoadPending, false);
        await _hive.setSetting(AppConstants.keyLiteRtGpuCrashDetected, true);
      }
      final hadPendingNpuLoad = isLiteRt && liteRtMode == 'ultra_performance' &&
          (_hive.getSetting<bool>(
                AppConstants.keyLiteRtNpuLoadPending,
                defaultValue: false,
              ) ??
              false);
      if (hadPendingNpuLoad) {
        await _hive.setSetting(AppConstants.keyLiteRtNpuLoadPending, false);
        await _hive.setSetting(AppConstants.keyLiteRtNpuCrashDetected, true);
      }
      final gpuCrashDetected = isLiteRt &&
          (_hive.getSetting<bool>(
                AppConstants.keyLiteRtGpuCrashDetected,
                defaultValue: false,
              ) ??
              false);
      final npuCrashDetected = isLiteRt && liteRtMode == 'ultra_performance' &&
          (_hive.getSetting<bool>(
                AppConstants.keyLiteRtNpuCrashDetected,
                defaultValue: false,
              ) ??
              false);
      // When NPU has crashed, fall through to GPU (auto_fast) for this session.
      final effectiveLiteRtMode = (liteRtMode == 'ultra_performance' && npuCrashDetected)
          ? 'auto_fast'
          : liteRtMode;
      final forceLiteRtCpu = isLiteRt &&
          (effectiveLiteRtMode == 'cpu_safe' ||
              (effectiveLiteRtMode == 'auto_fast' && gpuCrashDetected));
      final shouldTryLiteRtNpu = isLiteRt && !forceLiteRtCpu &&
          liteRtMode == 'ultra_performance' && !npuCrashDetected;
      final shouldTryLiteRtGpu = isLiteRt && !forceLiteRtCpu &&
          (effectiveLiteRtMode == 'auto_fast' || effectiveLiteRtMode == 'gpu_fast');

      await unloadModel();
      isLoadingModel.value = true;
      loadingModelName.value = modelName ?? modelPath.split('/').last;
      modelLoadProgress.value = 0.0;

      _engine = platform.InferenceEngine();

      final contextSize = _hive.getSetting<int>(
            AppConstants.keyContextSize,
            defaultValue: AppConstants.defaultContextSize,
          ) ??
          AppConstants.defaultContextSize;

      final finalContextSize = isLiteRt ? contextSize.clamp(512, 4096) : contextSize;

      final lastLoadedContext = _hive.getSetting<int>('last_loaded_context_size') ?? 0;
      final contextChanged = isLiteRt && lastLoadedContext != finalContextSize;

      final deviceTier = _getDeviceTier();
      final isTensorSoC = _getIsTensorSoC();

      final requestedModelName = modelName ?? modelPath.split('/').last;
      var activeModelName = requestedModelName;
      var result = await _loadModelOnEngine(
        modelPath: modelPath,
        modelRuntime: modelRuntime,
        contextSize: finalContextSize,
        deviceTier: deviceTier,
        isTensorSoC: isTensorSoC,
        liteRtPerformanceMode: effectiveLiteRtMode,
        forceLiteRtCpu: forceLiteRtCpu,
        clearLiteRtCache: hadPendingGpuLoad || hadPendingNpuLoad ||
            (isLiteRt && (gpuCrashDetected || npuCrashDetected)) || contextChanged,
        markLiteRtGpuPending: shouldTryLiteRtGpu,
        markLiteRtNpuPending: shouldTryLiteRtNpu,
        enableLiteRtVision: enableLiteRtVision,
      );

      if (!result.success &&
          result.message.toLowerCase().contains('model already loaded')) {
        final savedModelName =
            _hive.getSetting<String>(AppConstants.keyLocalModelName) ?? '';
        final adoptedModelName =
            savedModelName.isNotEmpty ? savedModelName : requestedModelName;
        activeModelName = adoptedModelName;
        result = platform.LoadResult(
          success: true,
          message: savedModelName == requestedModelName
              ? 'Model already loaded.'
              : 'A native model is already loaded. Unload it before loading another model.',
          runtime: modelRuntime ??
              _hive.getSetting<String>(AppConstants.keyLocalModelRuntime) ??
              '',
          backend:
              _hive.getSetting<String>(AppConstants.keyLocalModelBackend) ?? '',
        );
      }

      if (!result.success) {
        isModelLoaded.value = false;
        isLoadingModel.value = false;
        loadingModelName.value = '';
        modelLoadProgress.value = 0.0;
        loadedModelName.value = '';
        loadedModelRuntime.value = '';
        loadedBackend.value = '';
        gpuName.value = '';
        gpuLayersUsed.value = 0;
        isGpuAccelerated.value = false;
        Get.find<AppLogService>().error(
          'Local model load failed',
          details:
              'model=$requestedModelName, runtime=$runtime, backend=${result.backend}, message=${result.message}',
        );
        return result.message;
      }

      isModelLoaded.value = result.success;
      isLoadingModel.value = false;
      loadingModelName.value = '';
      modelLoadProgress.value = 1.0;
      loadedModelName.value = activeModelName;
      loadedModelRuntime.value = result.runtime;
      if (result.runtime == 'llama' || result.runtime == 'litert') {
        _sessionNativeRuntime = result.runtime;
      }
      loadedBackend.value = result.backend;
      gpuName.value = result.gpuName;
      gpuLayersUsed.value = result.gpuLayers;
      isGpuAccelerated.value = result.backend == 'gpu' || result.backend == 'npu' || result.gpuLayers > 0;
      if (isLiteRt && result.backend == 'gpu') {
        await _hive.setSetting(AppConstants.keyLiteRtGpuCrashDetected, false);
      }
      if (isLiteRt && result.backend == 'npu') {
        await _hive.setSetting(AppConstants.keyLiteRtNpuCrashDetected, false);
      }
      contextTokensUsed.value = 0;
      contextTokensTotal.value = finalContextSize;

      await _hive.setSetting(AppConstants.keyLocalModelPath, modelPath);
      await _hive.setSetting(
          AppConstants.keyLocalModelName, loadedModelName.value);
      await _hive.setSetting(
          AppConstants.keyLocalModelRuntime, loadedModelRuntime.value);
      await _hive.setSetting(
          AppConstants.keyLocalModelBackend, loadedBackend.value);

      if (isLiteRt) {
        await _hive.setSetting('last_loaded_context_size', finalContextSize);
      }

      return result.message;
    } catch (e) {
      isModelLoaded.value = false;
      isLoadingModel.value = false;
      loadingModelName.value = '';
      modelLoadProgress.value = 0.0;
      loadedBackend.value = '';
      Get.find<AppLogService>().error('Failed to load local model', details: e);
      return 'ERROR: Failed to load model — $e';
    }
  }

  Future<void> unloadModel() async {
    if (_isPteLoaded) {
      await Get.find<ExecuTorchService>().unload();
    }
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      await stopGeneration();
      await engine.dispose();
    }
    isModelLoaded.value = false;
    isVisionLoaded.value = false;
    loadedModelName.value = '';
    loadingModelName.value = '';
    loadedModelRuntime.value = '';
    loadedBackend.value = '';
    gpuLayersUsed.value = 0;
    isGpuAccelerated.value = false;
    gpuName.value = '';
    contextTokensUsed.value = 0;
    contextTokensTotal.value = 0;
    _sessionNativeRuntime = '';
  }

  Future<String> generate({
    required String prompt,
    String? systemPrompt,
    List<Map<String, String>>? conversationHistory,
    String source = 'chat',
    String? imagePath,
    String? audioPath,
    void Function(String token)? onToken,
  }) async {
    // Route to ExecuTorch when a .pte model is loaded
    if (_isPteLoaded) {
      return _generateExecuTorch(
        prompt: prompt,
        systemPrompt: systemPrompt,
        conversationHistory: conversationHistory,
        onToken: onToken,
      );
    }

    if (!supportsLocalInference || _engine == null || !isModelLoaded.value) {
      return 'ERROR: No model loaded. Go to Models tab to download and load one.';
    }

    if (isGenerating.value) {
      // Wait for previous generation
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (!isGenerating.value) break;
      }
      if (isGenerating.value) {
        await stopGeneration();
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }

    isGenerating.value = true;
    tokenCount.value = 0;
    tokensPerSecond.value = 0.0;
    generationSource.value = source;
    streamingText.value = '';

    final startTime = DateTime.now();
    DateTime? firstVisibleTokenAt;
    Timer? tokenFlushTimer;
    final tokenFlushBuffer = StringBuffer();

    void flushTokenBuffer() {
      if (tokenFlushBuffer.isEmpty) return;
      final text = tokenFlushBuffer.toString();
      tokenFlushBuffer.clear();
      onToken?.call(text);
    }

    try {
      final temperature = _hive.getSetting<double>(
            AppConstants.keyTemperature,
            defaultValue: AppConstants.defaultTemperature,
          ) ??
          AppConstants.defaultTemperature;

      final maxTokens = _hive.getSetting<int>(
            AppConstants.keyMaxTokens,
            defaultValue: AppConstants.defaultMaxTokens,
          ) ??
          AppConstants.defaultMaxTokens;

      final result = await _engine!.generate(
        prompt: prompt,
        conversationHistory: conversationHistory,
        systemPrompt: systemPrompt ?? AppConstants.systemPrompt,
        modelName: loadedModelName.value,
        maxTokens: maxTokens,
        temperature: temperature,
        imagePath: imagePath,
        audioPath: audioPath,
        onToken: (token) {
          firstVisibleTokenAt ??= DateTime.now();
          // Defer reactive updates to after the current build frame so that
          // newly-mounted Obx widgets have registered their listeners first,
          // avoiding the GetX "improper use" warning.
          Timer.run(() {
            tokenCount.value++;
            streamingText.value += token;
            final speedStart = firstVisibleTokenAt ?? startTime;
            final elapsedSeconds =
                DateTime.now().difference(speedStart).inMilliseconds / 1000.0;
            if (elapsedSeconds > 0) {
              tokensPerSecond.value = tokenCount.value / elapsedSeconds;
            }
          });
          if (loadedModelRuntime.value == 'litert') {
            tokenFlushBuffer.write(token);
            tokenFlushTimer ??= Timer(const Duration(milliseconds: 60), () {
              tokenFlushTimer = null;
              flushTokenBuffer();
            });
          } else {
            onToken?.call(token);
          }
        },
      );
      tokenFlushTimer?.cancel();
      flushTokenBuffer();

      await refreshContextInfo();
      isGenerating.value = false;
      generationSource.value = '';

      // Detect Tensor SoC + Gemma Q4_K_M corruption: model outputs only
      // special tokens and terminates immediately with empty result.
      if (result.trim().isEmpty &&
          tokenCount.value < 5 &&
          loadedModelName.value.toLowerCase().contains('gemma')) {
        final isTensor = _getIsTensorSoC();
        if (isTensor) {
          return '⚠️ This Gemma model is incompatible with your Pixel\'s Google Tensor chip. '
              'The Q4_K_M quantization format has a known bug on Tensor SoC that produces empty responses.\n\n'
              'Try one of these fixes:\n'
              '1. Download a Q4_0 or Q5_K_M version of the same model\n'
              '2. Use a different model (Qwen, Phi, or Llama-3)\n'
              '3. Switch to Cloud mode in Settings';
        }
      }

      return result;
    } catch (e) {
      isGenerating.value = false;
      generationSource.value = '';
      streamingText.value = '';
      tokenFlushTimer?.cancel();
      flushTokenBuffer();
      Get.find<AppLogService>().error('Local generation failed', details: e);
      final msg = e.toString();
      if (msg.contains('decode prompt') || msg.contains('Failed to decode')) {
        // Context window overflowed — reset native state so next call works.
        try { await resetConversation(); } catch (_) {}
        return '⚠️ Context window full — the conversation history exceeded this model\'s context limit. '
            'The context has been reset. Please resend your message.';
      }
      return 'ERROR: $e';
    }
  }

  Future<void> stopGeneration() async {
    isGenerating.value = false;
    tokenCount.value = 0;
    generationSource.value = '';
    streamingText.value = '';
    if (_isPteLoaded) {
      Get.find<ExecuTorchService>().stop();
    }
    final engine = _engine;
    if (engine != null) {
      unawaited(engine.stop().timeout(const Duration(seconds: 1)).catchError(
            (_) {},
          ));
    }
  }

  /// Reset the native conversation context. Call this whenever the user
  /// switches to a different chat session so old context doesn't leak.
  Future<void> resetConversation() async {
    final engine = _engine;
    if (engine != null) {
      await engine.resetConversation();
    }
  }

  Future<void> refreshContextInfo() async {
    if (!supportsLocalInference || _engine == null || !isModelLoaded.value) {
      return;
    }

    final info = await _engine!.getContextInfo();
    if (info == null) return;

    contextTokensUsed.value = info.tokensUsed;
    contextTokensTotal.value = info.contextSize;
  }

  String _getDeviceTier() {
    try {
      final device = Get.find<DeviceInfoService>();
      return device.deviceTier.value;
    } catch (_) {
      return 'mid';
    }
  }

  bool _getIsTensorSoC() {
    try {
      final device = Get.find<DeviceInfoService>();
      return device.isTensorSoC.value;
    } catch (_) {
      return false;
    }
  }

  Future<platform.LoadResult> _loadModelOnEngine({
    required String modelPath,
    required String? modelRuntime,
    required int contextSize,
    required String deviceTier,
    bool isTensorSoC = false,
    required String liteRtPerformanceMode,
    required bool forceLiteRtCpu,
    required bool clearLiteRtCache,
    required bool markLiteRtGpuPending,
    required bool markLiteRtNpuPending,
    required bool enableLiteRtVision,
  }) async {
    var gpuLoadFailed = false;
    try {
      if (markLiteRtNpuPending) {
        await _hive.setSetting(AppConstants.keyLiteRtNpuLoadPending, true);
      } else if (markLiteRtGpuPending) {
        await _hive.setSetting(AppConstants.keyLiteRtGpuLoadPending, true);
      }
      return await _engine!.loadModel(
        modelPath: modelPath,
        modelRuntime: modelRuntime,
        contextSize: contextSize,
        deviceTier: deviceTier,
        isTensorSoC: isTensorSoC,
        liteRtPerformanceMode: liteRtPerformanceMode,
        forceLiteRtCpu: forceLiteRtCpu,
        clearLiteRtCache: clearLiteRtCache,
        enableLiteRtVision: enableLiteRtVision,
        onProgress: (p) => modelLoadProgress.value = _normalizeProgress(p),
      );
    } catch (e) {
      // NPU failed → fall to GPU → fall to CPU
      if (markLiteRtNpuPending) {
        await _hive.setSetting(AppConstants.keyLiteRtNpuLoadPending, false);
        await _hive.setSetting(AppConstants.keyLiteRtNpuCrashDetected, true);
        print('[Inference] NPU load failed ($e) — falling back to GPU');
        try {
          modelLoadProgress.value = 0.0;
          return await _engine!.loadModel(
            modelPath: modelPath,
            modelRuntime: modelRuntime,
            contextSize: contextSize,
            deviceTier: deviceTier,
            isTensorSoC: isTensorSoC,
            liteRtPerformanceMode: 'auto_fast',
            forceLiteRtCpu: false,
            clearLiteRtCache: true,
            enableLiteRtVision: enableLiteRtVision,
            onProgress: (p) => modelLoadProgress.value = _normalizeProgress(p),
          );
        } catch (gpuError) {
          print('[Inference] GPU fallback also failed ($gpuError) — falling back to CPU');
          try {
            modelLoadProgress.value = 0.0;
            return await _engine!.loadModel(
              modelPath: modelPath,
              modelRuntime: modelRuntime,
              contextSize: contextSize,
              deviceTier: deviceTier,
              isTensorSoC: isTensorSoC,
              liteRtPerformanceMode: 'cpu_safe',
              forceLiteRtCpu: true,
              clearLiteRtCache: true,
              enableLiteRtVision: enableLiteRtVision,
              onProgress: (p) => modelLoadProgress.value = _normalizeProgress(p),
            );
          } catch (cpuError) {
            return platform.LoadResult(
              success: false,
              message: 'ERROR: Failed to load model - $cpuError',
            );
          }
        }
      }
      // GPU failed → CPU (auto_fast only)
      if (markLiteRtGpuPending && liteRtPerformanceMode == 'auto_fast') {
        await _hive.setSetting(AppConstants.keyLiteRtGpuLoadPending, false);
        await _hive.setSetting(AppConstants.keyLiteRtGpuCrashDetected, true);
        try {
          modelLoadProgress.value = 0.0;
          return await _engine!.loadModel(
            modelPath: modelPath,
            modelRuntime: modelRuntime,
            contextSize: contextSize,
            deviceTier: deviceTier,
            isTensorSoC: isTensorSoC,
            liteRtPerformanceMode: liteRtPerformanceMode,
            forceLiteRtCpu: true,
            clearLiteRtCache: true,
            enableLiteRtVision: enableLiteRtVision,
            onProgress: (p) => modelLoadProgress.value = _normalizeProgress(p),
          );
        } catch (cpuError) {
          return platform.LoadResult(
            success: false,
            message: 'ERROR: Failed to load model - $cpuError',
          );
        }
      }
      gpuLoadFailed = true;
      return platform.LoadResult(
        success: false,
        message: 'ERROR: Failed to load model - $e',
      );
    } finally {
      if (markLiteRtNpuPending) {
        await _hive.setSetting(AppConstants.keyLiteRtNpuLoadPending, false);
      } else if (markLiteRtGpuPending) {
        if (gpuLoadFailed) {
          await _hive.setSetting(AppConstants.keyLiteRtGpuCrashDetected, true);
        }
        await _hive.setSetting(AppConstants.keyLiteRtGpuLoadPending, false);
      }
    }
  }

  double _normalizeProgress(double progress) {
    if (progress.isNaN || progress.isInfinite) return 0.0;
    final normalized = progress > 1 ? progress / 100 : progress;
    return normalized.clamp(0.0, 1.0).toDouble();
  }

  String _runtimeFor(String modelPath, String? modelRuntime) {
    final runtime = modelRuntime?.toLowerCase();
    if (runtime == 'litert' || runtime == 'llama' || runtime == 'executorch') return runtime!;
    if (modelPath.toLowerCase().endsWith('.pte')) return 'executorch';
    return modelPath.toLowerCase().endsWith('.litertlm') ? 'litert' : 'llama';
  }

  // ── ExecuTorch / PTE delegation ──────────────────────────────────────

  Future<String> _loadExecuTorchModel(String modelPath, {String? modelName}) async {
    if (!Get.isRegistered<ExecuTorchService>()) {
      return 'ERROR: ExecuTorch service not available.';
    }
    final et = Get.find<ExecuTorchService>();
    final tokenizerPath = ExecuTorchService.findTokenizer(modelPath);
    final log = Get.find<AppLogService>();
    log.info('[ExecuTorch] Loading: $modelPath');
    if (tokenizerPath == null) {
      log.error('[ExecuTorch] No tokenizer found for $modelPath');
      return 'ERROR: No tokenizer found alongside ${modelPath.split('/').last}. '
          'Place tokenizer.bin in /storage/emulated/0/LLM-MODELS/ or the same folder.';
    }
    log.info('[ExecuTorch] Tokenizer: $tokenizerPath');

    // ExecuTorch's C++ open() cannot access external storage paths.
    // Copy tokenizer to internal storage via Kotlin (which can check MANAGE_EXTERNAL_STORAGE).
    String effectiveTokenizerPath = tokenizerPath;
    if (tokenizerPath.startsWith('/storage/') || tokenizerPath.startsWith('/sdcard/')) {
      final pteDir = modelPath.substring(0, modelPath.lastIndexOf('/'));
      final tokenizerName = tokenizerPath.split('/').last;
      final internalTokPath = '$pteDir/$tokenizerName';
      final internalTokFile = File(internalTokPath);
      final externalSize = File(tokenizerPath).lengthSync();
      // Re-copy if missing, suspiciously small, or external changed (size mismatch = stale cache).
      final needsCopy = !internalTokFile.existsSync()
          || internalTokFile.lengthSync() < 102400
          || internalTokFile.lengthSync() != externalSize;
      if (needsCopy) {
        log.info('[ExecuTorch] Copying tokenizer (${tokenizerPath.split('/').last}) to internal storage...');
        final copyError = await et.copyTokenizer(tokenizerPath, internalTokPath);
        if (copyError == 'PERMISSION_REQUIRED') {
          log.error('[ExecuTorch] All files access not granted — opening Settings');
          await et.openAllFilesSettings();
          return 'ERROR: Grant "All files access" to PrivateLM in Settings, then try loading the model again.';
        } else if (copyError != null) {
          log.error('[ExecuTorch] Tokenizer copy failed: $copyError');
          return 'ERROR: Could not copy tokenizer: $copyError';
        }
        final copiedSize = File(internalTokPath).lengthSync();
        log.info('[ExecuTorch] Tokenizer copied — ${(copiedSize / 1024 / 1024).toStringAsFixed(1)} MB at $internalTokPath');
      } else {
        log.info('[ExecuTorch] Using cached internal tokenizer (${(internalTokFile.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB)');
      }
      effectiveTokenizerPath = internalTokPath;
    }
    log.info('[ExecuTorch] LlmModule paths — model: $modelPath  tokenizer: $effectiveTokenizerPath');

    isLoadingModel.value = true;
    try {
      final error = await et.loadModel(modelPath, effectiveTokenizerPath);
      if (error != null) {
        log.error('[ExecuTorch] Load failed: $error');
        return 'ERROR: $error';
      }
      isModelLoaded.value = true;
      loadedModelName.value = modelName ?? modelPath.split('/').last;
      loadedModelRuntime.value = 'ExecuTorch QNN';
      loadedBackend.value = 'npu';
      isGpuAccelerated.value = true;
      gpuName.value = 'Qualcomm HTP (${et.htpArch.value})';
      log.info('[ExecuTorch] Loaded OK: ${loadedModelName.value}');
      return 'Model loaded — ExecuTorch QNN NPU (HTP ${et.htpArch.value})';
    } finally {
      isLoadingModel.value = false;
    }
  }

  bool get _isPteLoaded =>
      Get.isRegistered<ExecuTorchService>() &&
      Get.find<ExecuTorchService>().isLoaded.value;

  Future<String> _generateExecuTorch({
    required String prompt,
    String? systemPrompt,
    List<Map<String, String>>? conversationHistory,
    void Function(String token)? onToken,
  }) async {
    final et = Get.find<ExecuTorchService>();

    // Build Qwen chat prompt
    final sb = StringBuffer();
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      sb.write('<|im_start|>system\n$systemPrompt<|im_end|>\n');
    }
    if (conversationHistory != null) {
      for (final msg in conversationHistory) {
        final role = msg['role'] ?? 'user';
        final content = msg['content'] ?? '';
        sb.write('<|im_start|>$role\n$content<|im_end|>\n');
      }
    }
    sb.write('<|im_start|>user\n$prompt<|im_end|>\n<|im_start|>assistant\n');

    isGenerating.value = true;
    streamingText.value = '';
    try {
      final result = await et.generate(
        sb.toString(),
        maxTokens: 2048,
        onToken: (token) {
          streamingText.value += token;
          tokensPerSecond.value = et.tokensPerSecond.value;
          onToken?.call(token);
        },
      );
      tokensPerSecond.value = et.tokensPerSecond.value;
      return result;
    } finally {
      isGenerating.value = false;
      streamingText.value = '';
    }
  }
}
