import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/constants.dart';
import 'app_log_service.dart';
import 'device_info_service.dart';
import 'hive_service.dart';

class ToolCallingService extends GetxService {
  static const String protocolPrompt = '''
You can request a tool by returning only this JSON object:
{"tool_call":{"name":"tool_name","arguments":{}}}

Available tools:
- app_info: returns app name, package, and version.
- device_info: returns device tier, RAM estimate, chipset hints, and local inference recommendations.
- settings_summary: returns non-secret inference settings.
- calculator: evaluates simple arithmetic. Arguments: {"expression":"2 + 2 * 3"}.

When a tool result is provided, use it to answer the user's request. Do not
invent tool results. If another tool is needed, return another tool_call JSON
object.

Do not wrap tool calls in Markdown. If no tool is needed, answer normally.''';

  final HiveService _hive = Get.find<HiveService>();

  Future<ToolHandlingResult> handle(String rawOutput) async {
    final request = parseToolCall(rawOutput);
    if (request == null) {
      return ToolHandlingResult(output: rawOutput, toolWasCalled: false);
    }

    try {
      final result = await callTool(request.name, request.arguments);
      final rendered = renderToolResultForChat(request, result);
      return ToolHandlingResult(output: rendered, toolWasCalled: true);
    } catch (e) {
      Get.find<AppLogService>().warning(
        'Tool call failed',
        details: 'tool=${request.name}, error=$e',
      );
      return ToolHandlingResult(
        output: 'Tool "${request.name}" failed: $e',
        toolWasCalled: true,
      );
    }
  }

  Future<Map<String, dynamic>> callTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    switch (name) {
      case 'app_info':
        return _appInfo();
      case 'device_info':
        return _deviceInfo();
      case 'settings_summary':
        return _settingsSummary();
      case 'calculator':
        return _calculator(arguments);
      default:
        throw ArgumentError('Unknown tool: $name');
    }
  }

  ToolCallRequest? parseToolCall(String rawOutput) {
    final trimmed = rawOutput.trim();
    final jsonText = _extractJsonObject(trimmed);
    if (jsonText == null) return null;

    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) return null;
    final toolCall = decoded['tool_call'];
    if (toolCall is! Map<String, dynamic>) return null;
    final name = toolCall['name'];
    final args = toolCall['arguments'];
    if (name is! String || name.trim().isEmpty) return null;
    return ToolCallRequest(
      name: name.trim(),
      arguments: args is Map<String, dynamic> ? args : const {},
    );
  }

  String? _extractJsonObject(String text) {
    if (text.startsWith('{') && text.endsWith('}')) return text;

    final fenced = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').firstMatch(text);
    if (fenced != null) {
      final candidate = fenced.group(1)?.trim();
      if (candidate != null &&
          candidate.startsWith('{') &&
          candidate.endsWith('}')) {
        return candidate;
      }
    }

    return null;
  }

  Future<Map<String, dynamic>> _appInfo() async {
    final info = await PackageInfo.fromPlatform();
    return {
      'appName': info.appName,
      'packageName': info.packageName,
      'version': info.version,
      'buildNumber': info.buildNumber,
    };
  }

  Map<String, dynamic> _deviceInfo() {
    final device = Get.find<DeviceInfoService>();
    return {
      'deviceTier': device.deviceTier.value,
      'totalRamGB': device.totalRamGB.value,
      'availableRamGB': device.availableRamGB.value,
      'socHardware': device.socHardware.value,
      'isTensorSoC': device.isTensorSoC.value,
      'recommendedContextSize': device.recommendedContextSize,
      'recommendedMaxTokens': device.recommendedMaxTokens,
    };
  }

  Map<String, dynamic> _settingsSummary() {
    return {
      'inferenceMode':
          _hive.getSetting<String>(AppConstants.keyInferenceMode) ?? 'local',
      'contextSize': _hive.getSetting<int>(AppConstants.keyContextSize),
      'maxTokens': _hive.getSetting<int>(AppConstants.keyMaxTokens),
      'temperature': _hive.getSetting<double>(AppConstants.keyTemperature),
      'localModelName':
          _hive.getSetting<String>(AppConstants.keyLocalModelName) ?? '',
      'localModelRuntime':
          _hive.getSetting<String>(AppConstants.keyLocalModelRuntime) ?? '',
      'localModelBackend':
          _hive.getSetting<String>(AppConstants.keyLocalModelBackend) ?? '',
      'platform': Platform.operatingSystem,
    };
  }

  Map<String, dynamic> _calculator(Map<String, dynamic> arguments) {
    final expression = arguments['expression'];
    if (expression is! String || expression.trim().isEmpty) {
      throw ArgumentError('calculator requires an expression string');
    }
    final parser = _ArithmeticParser(expression);
    final value = parser.parse();
    return {'expression': expression, 'result': value};
  }

  String renderToolResultForModel(
    ToolCallRequest request,
    Map<String, dynamic> result,
  ) {
    const encoder = JsonEncoder.withIndent('  ');
    return 'Tool result for "${request.name}":\n${encoder.convert(result)}';
  }

  String renderToolResultForChat(
    ToolCallRequest request,
    Map<String, dynamic> result,
  ) {
    const encoder = JsonEncoder.withIndent('  ');
    return 'Tool result: ${request.name}\n\n```json\n${encoder.convert(result)}\n```';
  }
}

class ToolCallRequest {
  const ToolCallRequest({required this.name, required this.arguments});

  final String name;
  final Map<String, dynamic> arguments;
}

class ToolHandlingResult {
  const ToolHandlingResult({required this.output, required this.toolWasCalled});

  final String output;
  final bool toolWasCalled;
}

class _ArithmeticParser {
  _ArithmeticParser(this.source);

  final String source;
  int _index = 0;

  double parse() {
    final value = _parseExpression();
    _skipWhitespace();
    if (_index != source.length) {
      throw FormatException('Unexpected token at position $_index');
    }
    return value;
  }

  double _parseExpression() {
    var value = _parseTerm();
    while (true) {
      _skipWhitespace();
      if (_match('+')) {
        value += _parseTerm();
      } else if (_match('-')) {
        value -= _parseTerm();
      } else {
        return value;
      }
    }
  }

  double _parseTerm() {
    var value = _parseFactor();
    while (true) {
      _skipWhitespace();
      if (_match('*')) {
        value *= _parseFactor();
      } else if (_match('/')) {
        value /= _parseFactor();
      } else {
        return value;
      }
    }
  }

  double _parseFactor() {
    _skipWhitespace();
    if (_match('+')) return _parseFactor();
    if (_match('-')) return -_parseFactor();
    if (_match('(')) {
      final value = _parseExpression();
      _skipWhitespace();
      if (!_match(')')) {
        throw const FormatException('Missing closing parenthesis');
      }
      return value;
    }
    return _parseNumber();
  }

  double _parseNumber() {
    _skipWhitespace();
    final start = _index;
    while (_index < source.length) {
      final char = source.codeUnitAt(_index);
      final isDigit = char >= 48 && char <= 57;
      if (!isDigit && source[_index] != '.') break;
      _index++;
    }
    if (start == _index) {
      throw FormatException('Expected number at position $_index');
    }
    return double.parse(source.substring(start, _index));
  }

  bool _match(String token) {
    if (_index >= source.length || source[_index] != token) return false;
    _index++;
    return true;
  }

  void _skipWhitespace() {
    while (_index < source.length && source.codeUnitAt(_index) <= 32) {
      _index++;
    }
  }
}
