import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../core/constants.dart';
import 'app_log_service.dart';
import 'device_info_service.dart';
import 'document_extractor_service.dart';
import 'hive_service.dart';

enum ToolCallingMode { plan, build, agent }

enum ToolRisk { readOnly, write, shell, network, external }

class ToolCallingService extends GetxService {
  ToolCallingService() {
    _registerTools();
  }

  static const int planMaxRounds = 8;
  static const int agentMaxRounds = 16;

  static const List<String> advertisedCoreTools = [
    'web_search',
    'fetch_webpage',
    'http_request',
    'read_file',
    'list_directory',
    'find_files',
    'grep_in_files',
    'diff_files',
    'read_pdf',
    'read_docx',
    'read_json',
    'read_csv',
    'run_shell',
    'termux_exec',
    'git_status',
    'git_diff',
    'git_log',
    'get_system_info',
    'get_datetime',
    'get_clipboard',
    'calculate',
    'count_tokens',
    'encode_decode',
    'validate_data',
    'extract_json',
    'format_code',
    'analyze_log',
    'app_info',
    'device_info',
    'settings_summary',
    'hash_file',
  ];

  static const List<String> allToolNames = [
    'web_search',
    'fetch_webpage',
    'http_request',
    'download_file',
    'read_file',
    'write_file',
    'append_file',
    'edit_file',
    'delete_file',
    'move_file',
    'copy_file',
    'create_directory',
    'list_directory',
    'find_files',
    'grep_in_files',
    'diff_files',
    'patch_file',
    'zip_files',
    'unzip_file',
    'split_file',
    'compress_file',
    'decompress_file',
    'hash_file',
    'read_pdf',
    'read_docx',
    'read_xlsx',
    'read_pptx',
    'read_json',
    'read_csv',
    'read_sqlite',
    'write_docx',
    'write_xlsx',
    'run_shell',
    'write_and_run',
    'termux_exec',
    'termux_python',
    'termux_bash',
    'termux_open',
    'termux_check',
    'git_status',
    'git_diff',
    'git_log',
    'git_add',
    'git_commit',
    'git_push',
    'git_pull',
    'git_branch',
    'git_stash',
    'get_system_info',
    'get_datetime',
    'get_location',
    'get_weather',
    'get_clipboard',
    'set_clipboard',
    'send_notification',
    'list_processes',
    'get_contacts',
    'search_contacts',
    'get_calendar_events',
    'create_calendar_event',
    'extract_text_from_image',
    'calculate',
    'count_tokens',
    'encode_decode',
    'validate_data',
    'generate_password',
    'render_template',
    'extract_json',
    'format_code',
    'qr_code',
    'analyze_log',
    'convert_image',
    'search_memory',
    'search_documents',
    'benchmark_model',
    'cpanel_api',
    'whm_api',
    'ssh_exec',
    'send_email',
    'telegram_send',
    'app_info',
    'device_info',
    'settings_summary',
    'calculator',
  ];

  static final String protocolPrompt = '''
Tool calling is available through a ReAct loop.

To call a tool, output only:
[TOOL: tool_name]
{"arg":"value"}
[/TOOL]

The app executes the tool and injects:
[RESULT: tool_name]
{"result":"..."}
[/RESULT]

Then continue answering, or call another tool if needed.

Modes:
- Plan mode: read-only tools only. Dangerous tools are blocked.
- Build mode: all stable tools are available only when the user explicitly asks for Build mode; dangerous tools still return an approval-required result if UI approval is needed.
- Agent mode: same as Build mode with a larger loop budget.

Advertised core tools:
${advertisedCoreTools.join(', ')}

Other registered tools are available by exact name but are not listed here to keep context short.
Prefer tool calls for current file, device, web, calculation, data, git, or system facts. Do not invent tool results.''';

  final HiveService _hive = Get.find<HiveService>();
  final Map<String, _RegisteredTool> _tools = {};

  Future<ToolHandlingResult> handle(
    String rawOutput, {
    ToolCallingMode mode = ToolCallingMode.plan,
  }) async {
    final request = parseToolCall(rawOutput);
    if (request == null) {
      return ToolHandlingResult(output: rawOutput, toolWasCalled: false);
    }

    try {
      final result = await callTool(
        request.name,
        request.arguments,
        mode: mode,
      );
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
    Map<String, dynamic> arguments, {
    ToolCallingMode mode = ToolCallingMode.plan,
  }) async {
    final tool = _tools[name];
    if (tool == null) throw ArgumentError('Unknown tool: $name');
    if (!_isAllowed(tool, mode)) {
      return {
        'error': 'blocked_by_mode',
        'mode': mode.name,
        'tool': name,
        'reason': 'This tool is not available in Plan mode.',
      };
    }
    return tool.handler(arguments);
  }

  ToolCallRequest? parseToolCall(String rawOutput) {
    final trimmed = rawOutput.trim();
    final tagCall = _parseTaggedToolCall(trimmed);
    if (tagCall != null) return tagCall;

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

  String renderToolResultForModel(
    ToolCallRequest request,
    Map<String, dynamic> result,
  ) {
    const encoder = JsonEncoder.withIndent('  ');
    return '[RESULT: ${request.name}]\n${encoder.convert(result)}\n[/RESULT]';
  }

  String renderToolResultForChat(
    ToolCallRequest request,
    Map<String, dynamic> result,
  ) {
    const encoder = JsonEncoder.withIndent('  ');
    return 'Tool result: ${request.name}\n\n```json\n${encoder.convert(result)}\n```';
  }

  List<Map<String, dynamic>> describeTools() {
    return _tools.values
        .map(
          (tool) => {
            'name': tool.name,
            'risk': tool.risk.name,
            'implemented': tool.implemented,
            'advertised': advertisedCoreTools.contains(tool.name),
          },
        )
        .toList(growable: false);
  }

  bool _isAllowed(_RegisteredTool tool, ToolCallingMode mode) {
    if (mode != ToolCallingMode.plan) return true;
    return tool.risk == ToolRisk.readOnly || tool.risk == ToolRisk.network;
  }

  ToolCallRequest? _parseTaggedToolCall(String text) {
    final match = RegExp(
      r'^\[TOOL:\s*([A-Za-z0-9_\-]+)\s*\]\s*([\s\S]*?)\s*\[/TOOL\]$',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    final name = match.group(1)?.trim();
    final body = match.group(2)?.trim() ?? '{}';
    if (name == null || name.isEmpty) return null;
    final decoded = body.isEmpty ? const {} : jsonDecode(body);
    return ToolCallRequest(
      name: name,
      arguments: decoded is Map<String, dynamic> ? decoded : const {},
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

  void _registerTools() {
    _register('app_info', ToolRisk.readOnly, _appInfo);
    _register('device_info', ToolRisk.readOnly, (_) async => _deviceInfo());
    _register(
      'settings_summary',
      ToolRisk.readOnly,
      (_) async => _settingsSummary(),
    );
    _register('calculator', ToolRisk.readOnly, (_) async => _calculator(_));
    _register('calculate', ToolRisk.readOnly, (_) async => _calculator(_));
    _register('get_system_info', ToolRisk.readOnly, (_) async => _systemInfo());
    _register('get_datetime', ToolRisk.readOnly, (_) async => _dateTime(_));
    _register('get_clipboard', ToolRisk.readOnly, _getClipboard);
    _register('set_clipboard', ToolRisk.write, _setClipboard);
    _register('read_file', ToolRisk.readOnly, _readFile);
    _register('write_file', ToolRisk.write, _writeFile);
    _register('append_file', ToolRisk.write, _appendFile);
    _register('edit_file', ToolRisk.write, _editFile);
    _register('delete_file', ToolRisk.write, _deleteFile);
    _register('move_file', ToolRisk.write, _moveFile);
    _register('copy_file', ToolRisk.write, _copyFile);
    _register('create_directory', ToolRisk.write, _createDirectory);
    _register('list_directory', ToolRisk.readOnly, _listDirectory);
    _register('find_files', ToolRisk.readOnly, _findFiles);
    _register('grep_in_files', ToolRisk.readOnly, _grepInFiles);
    _register('diff_files', ToolRisk.readOnly, _diffFiles);
    _register('patch_file', ToolRisk.write, _patchFile);
    _register('zip_files', ToolRisk.write, _zipFiles);
    _register('unzip_file', ToolRisk.write, _unzipFile);
    _register('split_file', ToolRisk.write, _splitFile);
    _register('compress_file', ToolRisk.write, _zipFiles);
    _register('decompress_file', ToolRisk.write, _unzipFile);
    _register('hash_file', ToolRisk.readOnly, _hashFile);
    _register('read_pdf', ToolRisk.readOnly, _readDocument('pdf'));
    _register('read_docx', ToolRisk.readOnly, _readDocument('docx'));
    _register('read_json', ToolRisk.readOnly, _readJson);
    _register('read_csv', ToolRisk.readOnly, _readCsv);
    _register('fetch_webpage', ToolRisk.network, _fetchWebpage);
    _register('http_request', ToolRisk.network, _httpRequest);
    _register('download_file', ToolRisk.write, _downloadFile);
    _register('web_search', ToolRisk.network, _notImplemented('web_search'));
    _register('run_shell', ToolRisk.shell, _runShell);
    _register('write_and_run', ToolRisk.shell, _writeAndRun);
    _register('termux_exec', ToolRisk.shell, _runShell);
    _register('termux_python', ToolRisk.shell, _termuxPython);
    _register('termux_bash', ToolRisk.shell, _termuxBash);
    _register('termux_check', ToolRisk.readOnly, _termuxCheck);
    _register('termux_open', ToolRisk.external, _termuxOpen);
    _register('git_status', ToolRisk.readOnly, _git(['status', '--short']));
    _register('git_diff', ToolRisk.readOnly, _git(['diff', '--stat']));
    _register('git_log', ToolRisk.readOnly, _git(['log', '--oneline', '-20']));
    _register('git_add', ToolRisk.write, _gitFromArgs('add'));
    _register('git_commit', ToolRisk.write, _gitCommit);
    _register('git_push', ToolRisk.network, _gitFromArgs('push'));
    _register('git_pull', ToolRisk.network, _gitFromArgs('pull'));
    _register('git_branch', ToolRisk.readOnly, _gitFromArgs('branch'));
    _register('git_stash', ToolRisk.write, _gitFromArgs('stash'));
    _register('count_tokens', ToolRisk.readOnly, _countTokens);
    _register('encode_decode', ToolRisk.readOnly, _encodeDecode);
    _register('validate_data', ToolRisk.readOnly, _validateData);
    _register('generate_password', ToolRisk.readOnly, _generatePassword);
    _register('render_template', ToolRisk.readOnly, _renderTemplate);
    _register('extract_json', ToolRisk.readOnly, _extractJson);
    _register('format_code', ToolRisk.readOnly, _formatCode);
    _register('analyze_log', ToolRisk.readOnly, _analyzeLog);

    for (final name in allToolNames) {
      _tools.putIfAbsent(
        name,
        () => _RegisteredTool(
          name: name,
          risk: ToolRisk.external,
          implemented: false,
          handler: _notImplemented(name),
        ),
      );
    }
  }

  void _register(
    String name,
    ToolRisk risk,
    Future<Map<String, dynamic>> Function(Map<String, dynamic>) handler,
  ) {
    _tools[name] = _RegisteredTool(
      name: name,
      risk: risk,
      implemented: true,
      handler: handler,
    );
  }

  Future<Map<String, dynamic>> _appInfo(Map<String, dynamic> _) async {
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
      'registeredTools': _tools.length,
      'advertisedTools': advertisedCoreTools.length,
    };
  }

  Map<String, dynamic> _systemInfo() {
    return {
      'platform': Platform.operatingSystem,
      'version': Platform.operatingSystemVersion,
      'locale': Platform.localeName,
      'processors': Platform.numberOfProcessors,
      'executable': Platform.resolvedExecutable,
      'currentDirectory': Directory.current.path,
    };
  }

  Map<String, dynamic> _dateTime(Map<String, dynamic> args) {
    final now = DateTime.now();
    return {
      'local': now.toIso8601String(),
      'utc': now.toUtc().toIso8601String(),
      'formatted': DateFormat('yyyy-MM-dd HH:mm:ss Z').format(now),
      'timezone': now.timeZoneName,
      'timezoneOffsetMinutes': now.timeZoneOffset.inMinutes,
    };
  }

  Future<Map<String, dynamic>> _getClipboard(Map<String, dynamic> _) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return {'text': data?.text ?? ''};
  }

  Future<Map<String, dynamic>> _setClipboard(Map<String, dynamic> args) async {
    final text = _stringArg(args, 'text');
    await Clipboard.setData(ClipboardData(text: text));
    return {'ok': true, 'length': text.length};
  }

  Future<Map<String, dynamic>> _readFile(Map<String, dynamic> args) async {
    final path = _stringArg(args, 'path');
    final maxBytes = _intArg(args, 'max_bytes', 65536);
    final bytes = await File(path).openRead(0, maxBytes).fold<BytesBuilder>(
      BytesBuilder(copy: false),
      (builder, chunk) => builder..add(chunk),
    );
    return {
      'path': path,
      'text': utf8.decode(bytes.takeBytes(), allowMalformed: true),
      'truncated': await File(path).length() > maxBytes,
    };
  }

  Future<Map<String, dynamic>> _writeFile(Map<String, dynamic> args) async {
    final path = _stringArg(args, 'path');
    final content = _stringArg(args, 'content');
    await File(path).create(recursive: true);
    await File(path).writeAsString(content);
    return {'ok': true, 'path': path, 'bytes': utf8.encode(content).length};
  }

  Future<Map<String, dynamic>> _appendFile(Map<String, dynamic> args) async {
    final path = _stringArg(args, 'path');
    final content = _stringArg(args, 'content');
    await File(path).writeAsString(content, mode: FileMode.append);
    return {'ok': true, 'path': path, 'bytes': utf8.encode(content).length};
  }

  Future<Map<String, dynamic>> _editFile(Map<String, dynamic> args) async {
    final path = _stringArg(args, 'path');
    final oldText = _stringArg(args, 'old');
    final newText = _stringArg(args, 'new');
    final file = File(path);
    final text = await file.readAsString();
    if (!text.contains(oldText)) {
      return {'ok': false, 'error': 'old text not found', 'path': path};
    }
    await file.writeAsString(text.replaceFirst(oldText, newText));
    return {'ok': true, 'path': path};
  }

  Future<Map<String, dynamic>> _deleteFile(Map<String, dynamic> args) async {
    final path = _stringArg(args, 'path');
    await File(path).delete();
    return {'ok': true, 'path': path};
  }

  Future<Map<String, dynamic>> _moveFile(Map<String, dynamic> args) async {
    final from = _stringArg(args, 'from');
    final to = _stringArg(args, 'to');
    await File(from).rename(to);
    return {'ok': true, 'from': from, 'to': to};
  }

  Future<Map<String, dynamic>> _copyFile(Map<String, dynamic> args) async {
    final from = _stringArg(args, 'from');
    final to = _stringArg(args, 'to');
    await File(from).copy(to);
    return {'ok': true, 'from': from, 'to': to};
  }

  Future<Map<String, dynamic>> _createDirectory(Map<String, dynamic> args) async {
    final path = _stringArg(args, 'path');
    await Directory(path).create(recursive: true);
    return {'ok': true, 'path': path};
  }

  Future<Map<String, dynamic>> _listDirectory(Map<String, dynamic> args) async {
    final path = _stringArg(args, 'path', defaultValue: Directory.current.path);
    final recursive = args['recursive'] == true;
    final entries = await Directory(path)
        .list(recursive: recursive)
        .take(_intArg(args, 'limit', 200))
        .map(
          (entity) => {
            'path': entity.path,
            'type': entity is Directory ? 'directory' : 'file',
          },
        )
        .toList();
    return {'path': path, 'entries': entries};
  }

  Future<Map<String, dynamic>> _findFiles(Map<String, dynamic> args) async {
    final root = _stringArg(args, 'path', defaultValue: Directory.current.path);
    final pattern = _stringArg(args, 'pattern', defaultValue: '*');
    final regex = RegExp(_globToRegex(pattern), caseSensitive: false);
    final matches = <String>[];
    await for (final entity in Directory(root).list(recursive: true)) {
      if (entity is File && regex.hasMatch(p.basename(entity.path))) {
        matches.add(entity.path);
        if (matches.length >= _intArg(args, 'limit', 100)) break;
      }
    }
    return {'path': root, 'pattern': pattern, 'matches': matches};
  }

  Future<Map<String, dynamic>> _grepInFiles(Map<String, dynamic> args) async {
    final root = _stringArg(args, 'path', defaultValue: Directory.current.path);
    final pattern = _stringArg(args, 'pattern');
    final regex = RegExp(pattern, caseSensitive: args['case_sensitive'] == true);
    final results = <Map<String, dynamic>>[];
    await for (final entity in Directory(root).list(recursive: true)) {
      if (entity is! File) continue;
      try {
        final lines = await entity.readAsLines();
        for (var i = 0; i < lines.length; i++) {
          if (regex.hasMatch(lines[i])) {
            results.add({'path': entity.path, 'line': i + 1, 'text': lines[i]});
            if (results.length >= _intArg(args, 'limit', 100)) {
              return {'matches': results};
            }
          }
        }
      } catch (_) {}
    }
    return {'matches': results};
  }

  Future<Map<String, dynamic>> _diffFiles(Map<String, dynamic> args) async {
    final a = await File(_stringArg(args, 'a')).readAsLines();
    final b = await File(_stringArg(args, 'b')).readAsLines();
    final changes = <String>[];
    final maxLen = max(a.length, b.length);
    for (var i = 0; i < maxLen; i++) {
      final left = i < a.length ? a[i] : null;
      final right = i < b.length ? b[i] : null;
      if (left != right) {
        changes.add('- ${left ?? ''}');
        changes.add('+ ${right ?? ''}');
      }
      if (changes.length >= _intArg(args, 'limit', 200)) break;
    }
    return {'diff': changes.join('\n')};
  }

  Future<Map<String, dynamic>> _patchFile(Map<String, dynamic> args) async {
    final path = _stringArg(args, 'path');
    final search = _stringArg(args, 'search');
    final replace = _stringArg(args, 'replace');
    final file = File(path);
    final text = await file.readAsString();
    final count = search.allMatches(text).length;
    await file.writeAsString(text.replaceAll(search, replace));
    return {'ok': true, 'path': path, 'replacements': count};
  }

  Future<Map<String, dynamic>> _zipFiles(Map<String, dynamic> args) async {
    final output = _stringArg(args, 'output');
    final paths = _stringListArg(args, 'paths');
    final encoder = ZipFileEncoder()..create(output);
    try {
      for (final path in paths) {
        final type = FileSystemEntity.typeSync(path);
        if (type == FileSystemEntityType.directory) {
          encoder.addDirectory(Directory(path));
        } else if (type == FileSystemEntityType.file) {
          encoder.addFile(File(path));
        }
      }
    } finally {
      encoder.close();
    }
    return {'ok': true, 'output': output};
  }

  Future<Map<String, dynamic>> _unzipFile(Map<String, dynamic> args) async {
    final path = _stringArg(args, 'path');
    final output = _stringArg(args, 'output');
    await extractFileToDisk(path, output);
    return {'ok': true, 'path': path, 'output': output};
  }

  Future<Map<String, dynamic>> _splitFile(Map<String, dynamic> args) async {
    final path = _stringArg(args, 'path');
    final outputDir = _stringArg(args, 'output_dir');
    final chunkBytes = _intArg(args, 'chunk_bytes', 1024 * 1024);
    await Directory(outputDir).create(recursive: true);
    final bytes = await File(path).readAsBytes();
    final outputs = <String>[];
    for (var offset = 0, part = 0; offset < bytes.length; offset += chunkBytes) {
      final end = min(offset + chunkBytes, bytes.length);
      final out = p.join(outputDir, '${p.basename(path)}.part$part');
      await File(out).writeAsBytes(bytes.sublist(offset, end));
      outputs.add(out);
      part++;
    }
    return {'ok': true, 'parts': outputs};
  }

  Future<Map<String, dynamic>> _hashFile(Map<String, dynamic> args) async {
    final path = _stringArg(args, 'path');
    final bytes = await File(path).readAsBytes();
    return {
      'path': path,
      'sha256': sha256.convert(bytes).toString(),
      'md5': md5.convert(bytes).toString(),
      'bytes': bytes.length,
    };
  }

  Future<Map<String, dynamic>> Function(Map<String, dynamic>) _readDocument(
    String extension,
  ) {
    return (args) async {
      final path = _stringArg(args, 'path');
      final text = await DocumentExtractorService.extractText(path, extension);
      return {'path': path, 'text': _truncate(text, _intArg(args, 'limit', 50000))};
    };
  }

  Future<Map<String, dynamic>> _readJson(Map<String, dynamic> args) async {
    final path = _stringArg(args, 'path');
    return {'path': path, 'data': jsonDecode(await File(path).readAsString())};
  }

  Future<Map<String, dynamic>> _readCsv(Map<String, dynamic> args) async {
    final path = _stringArg(args, 'path');
    final lines = await File(path).readAsLines();
    final rows = lines
        .take(_intArg(args, 'limit', 100))
        .map((line) => line.split(',').map((cell) => cell.trim()).toList())
        .toList();
    return {'path': path, 'rows': rows, 'truncated': lines.length > rows.length};
  }

  Future<Map<String, dynamic>> _fetchWebpage(Map<String, dynamic> args) async {
    final url = Uri.parse(_stringArg(args, 'url'));
    final response = await http.get(url).timeout(const Duration(seconds: 20));
    return {
      'url': url.toString(),
      'status': response.statusCode,
      'body': _truncate(response.body, _intArg(args, 'limit', 50000)),
    };
  }

  Future<Map<String, dynamic>> _httpRequest(Map<String, dynamic> args) async {
    final method = _stringArg(args, 'method', defaultValue: 'GET').toUpperCase();
    final url = Uri.parse(_stringArg(args, 'url'));
    final headers = (args['headers'] as Map?)?.cast<String, String>();
    final body = args['body']?.toString();
    final request = http.Request(method, url)
      ..headers.addAll(headers ?? const {})
      ..body = body ?? '';
    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamed);
    return {
      'status': response.statusCode,
      'headers': response.headers,
      'body': _truncate(response.body, _intArg(args, 'limit', 50000)),
    };
  }

  Future<Map<String, dynamic>> _downloadFile(Map<String, dynamic> args) async {
    final url = Uri.parse(_stringArg(args, 'url'));
    final path = _stringArg(args, 'path');
    final response = await http.get(url).timeout(const Duration(minutes: 2));
    await File(path).create(recursive: true);
    await File(path).writeAsBytes(response.bodyBytes);
    return {'ok': true, 'path': path, 'status': response.statusCode};
  }

  Future<Map<String, dynamic>> _runShell(Map<String, dynamic> args) async {
    final command = _stringArg(args, 'command');
    return _runCommand('/system/bin/sh', ['-c', command], args);
  }

  Future<Map<String, dynamic>> _writeAndRun(Map<String, dynamic> args) async {
    final path = _stringArg(args, 'path');
    await _writeFile(args);
    return _runCommand('/system/bin/sh', [path], args);
  }

  Future<Map<String, dynamic>> _termuxPython(Map<String, dynamic> args) async {
    final code = _stringArg(args, 'code');
    return _runCommand('python', ['-c', code], args);
  }

  Future<Map<String, dynamic>> _termuxBash(Map<String, dynamic> args) async {
    final command = _stringArg(args, 'command');
    return _runCommand('bash', ['-lc', command], args);
  }

  Future<Map<String, dynamic>> _termuxCheck(Map<String, dynamic> _) async {
    return {
      'termux': Platform.environment['PREFIX']?.contains('com.termux') == true,
      'prefix': Platform.environment['PREFIX'],
      'home': Platform.environment['HOME'],
    };
  }

  Future<Map<String, dynamic>> _termuxOpen(Map<String, dynamic> args) async {
    final target = _stringArg(args, 'target');
    return _runCommand('termux-open', [target], args);
  }

  Future<Map<String, dynamic>> Function(Map<String, dynamic>) _git(
    List<String> baseArgs,
  ) {
    return (args) => _runCommand(
          'git',
          baseArgs,
          args,
          workingDirectory: args['path']?.toString(),
        );
  }

  Future<Map<String, dynamic>> Function(Map<String, dynamic>) _gitFromArgs(
    String subcommand,
  ) {
    return (args) {
      final extra = _stringListArg(args, 'args', allowEmpty: true);
      return _runCommand(
        'git',
        [subcommand, ...extra],
        args,
        workingDirectory: args['path']?.toString(),
      );
    };
  }

  Future<Map<String, dynamic>> _gitCommit(Map<String, dynamic> args) {
    final message = _stringArg(args, 'message');
    return _runCommand(
      'git',
      ['commit', '-m', message],
      args,
      workingDirectory: args['path']?.toString(),
    );
  }

  Future<Map<String, dynamic>> _runCommand(
    String executable,
    List<String> arguments,
    Map<String, dynamic> args, {
    String? workingDirectory,
  }) async {
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: false,
    ).timeout(Duration(seconds: _intArg(args, 'timeout_seconds', 30)));
    return {
      'exitCode': result.exitCode,
      'stdout': _truncate(result.stdout.toString(), _intArg(args, 'limit', 20000)),
      'stderr': _truncate(result.stderr.toString(), _intArg(args, 'limit', 20000)),
    };
  }

  Map<String, dynamic> _calculator(Map<String, dynamic> arguments) {
    final expression = arguments['expression'] ?? arguments['input'];
    if (expression is! String || expression.trim().isEmpty) {
      throw ArgumentError('calculate requires an expression string');
    }
    final parser = _ArithmeticParser(expression);
    final value = parser.parse();
    return {'expression': expression, 'result': value};
  }

  Future<Map<String, dynamic>> _countTokens(Map<String, dynamic> args) async {
    final text = _stringArg(args, 'text');
    return {
      'chars': text.length,
      'words': RegExp(r'\S+').allMatches(text).length,
      'estimatedTokens': (text.length / 4).ceil(),
    };
  }

  Future<Map<String, dynamic>> _encodeDecode(Map<String, dynamic> args) async {
    final mode = _stringArg(args, 'mode');
    final text = _stringArg(args, 'text');
    switch (mode) {
      case 'base64_encode':
        return {'text': base64Encode(utf8.encode(text))};
      case 'base64_decode':
        return {'text': utf8.decode(base64Decode(text), allowMalformed: true)};
      case 'url_encode':
        return {'text': Uri.encodeComponent(text)};
      case 'url_decode':
        return {'text': Uri.decodeComponent(text)};
      default:
        throw ArgumentError('Unsupported encode_decode mode: $mode');
    }
  }

  Future<Map<String, dynamic>> _validateData(Map<String, dynamic> args) async {
    final text = args['text']?.toString() ?? '';
    final issues = <String>[];
    if (text.trim().isEmpty) issues.add('empty input');
    try {
      jsonDecode(text);
    } catch (_) {
      if (text.trim().startsWith('{') || text.trim().startsWith('[')) {
        issues.add('invalid json');
      }
    }
    return {'valid': issues.isEmpty, 'issues': issues};
  }

  Future<Map<String, dynamic>> _generatePassword(Map<String, dynamic> args) async {
    final length = _intArg(args, 'length', 24);
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#%^*-_=+';
    final random = Random.secure();
    return {
      'password': List.generate(
        length,
        (_) => chars[random.nextInt(chars.length)],
      ).join(),
    };
  }

  Future<Map<String, dynamic>> _renderTemplate(Map<String, dynamic> args) async {
    var template = _stringArg(args, 'template');
    final values = (args['values'] as Map?) ?? const {};
    values.forEach((key, value) {
      template = template.replaceAll('{{$key}}', value.toString());
    });
    return {'text': template};
  }

  Future<Map<String, dynamic>> _extractJson(Map<String, dynamic> args) async {
    final text = _stringArg(args, 'text');
    final jsonText = _extractJsonObject(text);
    if (jsonText == null) return {'found': false};
    return {'found': true, 'data': jsonDecode(jsonText)};
  }

  Future<Map<String, dynamic>> _formatCode(Map<String, dynamic> args) async {
    final code = _stringArg(args, 'code');
    final language = args['language']?.toString() ?? '';
    return {
      'language': language,
      'code': code.replaceAll(RegExp(r'[ \t]+$'), '').trimRight(),
    };
  }

  Future<Map<String, dynamic>> _analyzeLog(Map<String, dynamic> args) async {
    final text = _stringArg(args, 'text');
    final lines = const LineSplitter().convert(text);
    final errors = lines.where((line) => line.toLowerCase().contains('error'));
    final warnings = lines.where((line) => line.toLowerCase().contains('warn'));
    return {
      'lineCount': lines.length,
      'errorCount': errors.length,
      'warningCount': warnings.length,
      'sampleErrors': errors.take(10).toList(),
      'sampleWarnings': warnings.take(10).toList(),
    };
  }

  Future<Map<String, dynamic>> Function(Map<String, dynamic>) _notImplemented(
    String name,
  ) {
    return (_) async => {
          'error': 'not_implemented',
          'tool': name,
          'reason':
              'The tool is registered for SA-AI compatibility but needs a platform plugin, API credentials, or a dedicated implementation.',
        };
  }

  String _stringArg(
    Map<String, dynamic> args,
    String key, {
    String? defaultValue,
  }) {
    final value = args[key];
    if (value == null && defaultValue != null) return defaultValue;
    if (value is String) return value;
    throw ArgumentError('Missing string argument "$key"');
  }

  int _intArg(Map<String, dynamic> args, String key, int defaultValue) {
    final value = args[key];
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  List<String> _stringListArg(
    Map<String, dynamic> args,
    String key, {
    bool allowEmpty = false,
  }) {
    final value = args[key];
    if (value is List) return value.map((item) => item.toString()).toList();
    if (value == null && allowEmpty) return const [];
    throw ArgumentError('Missing list argument "$key"');
  }

  String _truncate(String text, int limit) {
    if (text.length <= limit) return text;
    return '${text.substring(0, limit)}\n...[truncated ${text.length - limit} chars]';
  }

  String _globToRegex(String glob) {
    return '^${RegExp.escape(glob).replaceAll(r'\*', '.*').replaceAll(r'\?', '.')}\$';
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

class _RegisteredTool {
  const _RegisteredTool({
    required this.name,
    required this.risk,
    required this.implemented,
    required this.handler,
  });

  final String name;
  final ToolRisk risk;
  final bool implemented;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) handler;
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
