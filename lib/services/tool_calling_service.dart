import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:device_calendar/device_calendar.dart' hide Event;
import 'package:device_calendar/device_calendar.dart' as dc show Event;
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../core/constants.dart';
import 'app_log_service.dart';
import 'cloud_service.dart';
import 'device_info_service.dart';
import 'document_extractor_service.dart';
import 'hive_service.dart';
import 'mcp_service.dart';
import 'rag_service.dart';
import 'phone_action_service.dart';

enum ToolCallingMode { plan, build, agent, subagent }

enum ToolRisk { readOnly, write, shell, network, external }

class ToolCallingService extends GetxService {
  ToolCallingService() {
    _registerTools();
  }

  static const int planMaxRounds = 8;
  static const int agentMaxRounds = 16;
  static const int subagentMaxRounds = 32;

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
    'read_xlsx',
    'read_json',
    'read_csv',
    'run_shell',
    'termux_exec',
    'git_status',
    'git_diff',
    'git_log',
    'get_system_info',
    'get_datetime',
    'get_location',
    'get_weather',
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
    'mcp_add_server',
    'mcp_initialize',
    'mcp_list_tools',
    'mcp_call_tool',
    'mcp_list_servers',
    'get_calendar_events',
    'create_calendar_event',
    'get_contacts',
    'search_contacts',
    'rag_set_embed_model',
    'rag_index_file',
    'rag_index_text',
    'rag_search',
    'rag_list_sources',
    'rag_status',
    'spawn_agent',
    // Phone automation (OpenDroid accessibility bridge)
    'check_accessibility',
    'send_whatsapp',
    'send_sms',
    'make_call',
    'get_screen_text',
    'click_on_screen',
    'find_and_click',
    'find_and_type',
    'take_screenshot',
    'open_app',
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
    'mcp_add_server',
    'mcp_initialize',
    'mcp_list_tools',
    'mcp_call_tool',
    'mcp_list_servers',
    'mcp_remove_server',
    'rag_set_embed_model',
    'rag_index_file',
    'rag_index_text',
    'rag_search',
    'rag_list_sources',
    'rag_status',
    'rag_clear',
    'spawn_agent',
    // Phone automation (OpenDroid accessibility bridge)
    'check_accessibility',
    'send_whatsapp',
    'send_sms',
    'make_call',
    'get_screen_text',
    'click_on_screen',
    'find_and_click',
    'find_and_type',
    'take_screenshot',
    'open_app',
  ];

  static const String planningPrompt = '''
When the user asks you to perform a multi-step task, you may emit a plan using this format:

[PLAN]
step_1: <description>
step_2: <description>
...
[/PLAN]

Then execute each step by calling the appropriate tool. After each tool result, you may use {{step_N_output}} to refer to prior step outputs. After all steps, write a [SYNTHESIZE] block summarizing the results.

verify: <success_check> where success_check can be: contains(<text>), not_empty, file_exists(<path>), exit_code_ok
''';

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
Prefer tool calls for current file, device, web, calculation, data, git, or system facts. Do not invent tool results.

Phone automation tools (require accessibility permission):
- check_accessibility: check if accessibility service is enabled
- get_screen_text: read all visible text on the current screen
- take_screenshot: capture the current screen as base64 image
- send_whatsapp {"contact":"...","message":"..."}: send WhatsApp message
- send_sms {"to":"...","message":"..."}: send SMS
- make_call {"to":"..."}: make a phone call
- open_app {"package_name":"..."}: launch an app by package name
- find_and_click {"text":"..."}: tap a UI element by visible text
- find_and_type {"label":"...","content":"..."}: type into a field
- click_on_screen {"x":0,"y":0}: tap at screen coordinates
Always use get_screen_text or take_screenshot when the user asks what is on their screen.''';

  static const _termuxChannel = MethodChannel('com.orailnoor.privatelm/termux_bridge');

  // Set by chat controller to intercept dangerous tool calls
  Future<bool> Function(String toolName, Map<String, dynamic> args)? approvalHandler;

  static const Set<ToolRisk> _risksNeedingApproval = {ToolRisk.shell, ToolRisk.external};

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
    if (approvalHandler != null && _risksNeedingApproval.contains(tool.risk) && mode != ToolCallingMode.plan) {
      final approved = await approvalHandler!(name, arguments);
      if (!approved) return {'error': 'user_denied', 'tool': name, 'message': 'User denied this tool call'};
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
    if (mode == ToolCallingMode.plan) {
      return tool.risk == ToolRisk.readOnly || tool.risk == ToolRisk.network;
    }
    return true;
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
    // Phone automation (OpenDroid accessibility bridge)
    _register('send_whatsapp', ToolRisk.external, _sendWhatsApp);
    _register('send_sms', ToolRisk.external, _sendSms);
    _register('make_call', ToolRisk.external, _makeCall);
    _register('get_screen_text', ToolRisk.readOnly, (_) async => _getScreenText());
    _register('click_on_screen', ToolRisk.external, _clickOnScreen);
    _register('find_and_click', ToolRisk.external, _findAndClick);
    _register('find_and_type', ToolRisk.external, _findAndType);
    _register('take_screenshot', ToolRisk.readOnly, (_) async => _takeScreenshot());
    _register('open_app', ToolRisk.external, _openApp);
    _register('check_accessibility', ToolRisk.readOnly, (_) async => _checkAccessibility());
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
    _register('get_location', ToolRisk.network, _getApproxLocation);
    _register('get_weather', ToolRisk.network, _getWeather);
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
    _register('read_xlsx', ToolRisk.readOnly, _readXlsx);
    _register('read_json', ToolRisk.readOnly, _readJson);
    _register('read_csv', ToolRisk.readOnly, _readCsv);
    _register('write_xlsx', ToolRisk.write, _writeXlsx);
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
    _register('mcp_add_server', ToolRisk.network, _mcpAddServer);
    _register('mcp_initialize', ToolRisk.network, _mcpInitialize);
    _register('mcp_list_tools', ToolRisk.network, _mcpListTools);
    _register('mcp_call_tool', ToolRisk.network, _mcpCallTool);
    _register('mcp_list_servers', ToolRisk.readOnly, _mcpListServers);
    _register('mcp_remove_server', ToolRisk.write, _mcpRemoveServer);
    _register('read_sqlite', ToolRisk.readOnly, _readSqlite);
    _register('read_pptx', ToolRisk.readOnly, _readPptx);
    _register('write_docx', ToolRisk.write, _writeDocx);
    if (Platform.isAndroid || Platform.isIOS) {
      _register('get_calendar_events', ToolRisk.readOnly, _getCalendarEvents);
      _register('create_calendar_event', ToolRisk.write, _createCalendarEvent);
      _register('get_contacts', ToolRisk.readOnly, _getContacts);
      _register('search_contacts', ToolRisk.readOnly, _searchContacts);
    }
    _register('rag_set_embed_model', ToolRisk.write, _ragSetEmbedModel);
    _register('rag_index_file', ToolRisk.write, _ragIndexFile);
    _register('rag_index_text', ToolRisk.write, _ragIndexText);
    _register('rag_search', ToolRisk.readOnly, _ragSearch);
    _register('rag_list_sources', ToolRisk.readOnly, _ragListSources);
    _register('rag_status', ToolRisk.readOnly, _ragStatus);
    _register('rag_clear', ToolRisk.write, _ragClear);
    _register('spawn_agent', ToolRisk.network, _spawnAgent);

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

  // ── Phone Automation (OpenDroid bridge) ────────────────────────────

  PhoneActionService? get _phone =>
      Get.isRegistered<PhoneActionService>() ? Get.find<PhoneActionService>() : null;

  Future<Map<String, dynamic>> _checkAccessibility() async {
    final svc = _phone;
    if (svc == null) return {'enabled': false, 'error': 'PhoneActionService not initialized'};
    await svc.refreshAccessibilityStatus();
    return {
      'enabled': svc.isAccessibilityEnabled.value,
      'message': svc.isAccessibilityEnabled.value
          ? 'Accessibility service is active'
          : 'Go to Settings → Accessibility → PrivateLM Agent and enable it',
    };
  }

  Future<Map<String, dynamic>> _sendWhatsApp(Map<String, dynamic> p) async {
    final contact = p['contact']?.toString() ?? '';
    final message = p['message']?.toString() ?? '';
    if (contact.isEmpty || message.isEmpty) {
      return {'error': 'contact and message are required'};
    }
    final err = await _phone?.sendWhatsApp(contact, message);
    return err == null ? {'success': true} : {'error': err};
  }

  Future<Map<String, dynamic>> _sendSms(Map<String, dynamic> p) async {
    final to = p['to']?.toString() ?? '';
    final message = p['message']?.toString() ?? '';
    if (to.isEmpty || message.isEmpty) return {'error': 'to and message are required'};
    final err = await _phone?.sendSms(to, message);
    return err == null ? {'success': true} : {'error': err};
  }

  Future<Map<String, dynamic>> _makeCall(Map<String, dynamic> p) async {
    final to = p['to']?.toString() ?? '';
    if (to.isEmpty) return {'error': 'to is required'};
    final err = await _phone?.makeCall(to);
    return err == null ? {'success': true} : {'error': err};
  }

  Future<Map<String, dynamic>> _getScreenText() async {
    final text = await _phone?.getScreenText() ?? 'PhoneActionService not available';
    return {'text': text};
  }

  Future<Map<String, dynamic>> _clickOnScreen(Map<String, dynamic> p) async {
    final x = (p['x'] as num?)?.toDouble() ?? 0.0;
    final y = (p['y'] as num?)?.toDouble() ?? 0.0;
    final ok = await _phone?.clickOnScreen(x, y) ?? false;
    return {'success': ok};
  }

  Future<Map<String, dynamic>> _findAndClick(Map<String, dynamic> p) async {
    final text = p['text']?.toString() ?? '';
    if (text.isEmpty) return {'error': 'text is required'};
    final ok = await _phone?.findAndClick(text) ?? false;
    return {'success': ok};
  }

  Future<Map<String, dynamic>> _findAndType(Map<String, dynamic> p) async {
    final label = p['label']?.toString() ?? '';
    final content = p['content']?.toString() ?? '';
    if (label.isEmpty || content.isEmpty) return {'error': 'label and content are required'};
    final ok = await _phone?.findAndType(label, content) ?? false;
    return {'success': ok};
  }

  Future<Map<String, dynamic>> _takeScreenshot() async {
    final b64 = await _phone?.takeScreenshot();
    return b64 != null ? {'screenshot_base64': b64} : {'error': 'Screenshot failed or accessibility not enabled'};
  }

  Future<Map<String, dynamic>> _openApp(Map<String, dynamic> p) async {
    final pkg = p['package_name']?.toString() ?? '';
    if (pkg.isEmpty) return {'error': 'package_name is required'};
    final err = await _phone?.openApp(pkg);
    return err == null ? {'success': true} : {'error': err};
  }

  // ── End Phone Automation ────────────────────────────────────────────

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

  Future<Map<String, dynamic>> _getApproxLocation(
    Map<String, dynamic> args,
  ) async {
    final response = await http
        .get(Uri.parse('http://ip-api.com/json/?fields=status,city,regionName,country,lat,lon,timezone,query'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      return {
        'error': 'location_lookup_failed',
        'status': response.statusCode,
        'body': _truncate(response.body, 1000),
      };
    }

    final data = jsonDecode(response.body);
    if (data is! Map || data['status'] != 'success') {
      return {'error': 'invalid_location_response'};
    }

    return {
      'source': 'ip_geolocation',
      'city': data['city'],
      'region': data['regionName'],
      'country': data['country'],
      'latitude': data['lat'],
      'longitude': data['lon'],
      'timezone': data['timezone'],
      'accuracy': 'approximate',
    };
  }

  Future<Map<String, dynamic>> _getWeather(Map<String, dynamic> args) async {
    var location = args['location']?.toString().trim() ?? '';
    if (location.isEmpty) {
      final approx = await _getApproxLocation(args);
      final city = approx['city']?.toString();
      final region = approx['region']?.toString();
      final country = approx['country']?.toString();
      location = [
        if (city != null && city.isNotEmpty) city,
        if (region != null && region.isNotEmpty) region,
        if (country != null && country.isNotEmpty) country,
      ].join(', ');
    }
    if (location.isEmpty) {
      return {
        'error': 'location_required',
        'reason':
            'No location argument was provided and approximate location lookup failed.',
      };
    }

    final uri = Uri.https('wttr.in', '/$location', {'format': 'j1'});
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      return {
        'error': 'weather_lookup_failed',
        'location': location,
        'status': response.statusCode,
        'body': _truncate(response.body, 1000),
      };
    }

    final data = jsonDecode(response.body);
    if (data is! Map) return {'error': 'invalid_weather_response'};

    Map? firstMap(Object? value) {
      if (value is List && value.isNotEmpty && value.first is Map) {
        return value.first as Map;
      }
      return null;
    }

    final current = firstMap(data['current_condition']);
    final nearest = firstMap(data['nearest_area']);
    final weather = firstMap(data['weather']);
    final astronomy = weather == null ? null : firstMap(weather['astronomy']);

    String? textFromList(Object? value) {
      if (value is List && value.isNotEmpty && value.first is Map) {
        return (value.first as Map)['value']?.toString();
      }
      return null;
    }

    return {
      'source': 'wttr.in',
      'requestedLocation': location,
      'resolvedLocation': nearest is Map
          ? {
              'area': textFromList(nearest['areaName']),
              'region': textFromList(nearest['region']),
              'country': textFromList(nearest['country']),
              'latitude': nearest['latitude'],
              'longitude': nearest['longitude'],
            }
          : null,
      'current': current is Map
          ? {
              'temperatureC': current['temp_C'],
              'temperatureF': current['temp_F'],
              'feelsLikeC': current['FeelsLikeC'],
              'feelsLikeF': current['FeelsLikeF'],
              'humidity': current['humidity'],
              'windKmph': current['windspeedKmph'],
              'description': textFromList(current['weatherDesc']),
              'observationTime': current['observation_time'],
            }
          : null,
      'today': weather is Map
          ? {
              'date': weather['date'],
              'maxC': weather['maxtempC'],
              'minC': weather['mintempC'],
              'maxF': weather['maxtempF'],
              'minF': weather['mintempF'],
              'sunrise': astronomy?['sunrise'],
              'sunset': astronomy?['sunset'],
            }
          : null,
      'accuracy':
          args['location'] == null ? 'approximate_ip_location' : 'requested',
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
    final patch = _stringArg(args, 'patch');
    final file = File(path);
    if (!file.existsSync()) return {'error': 'File not found: $path'};
    var lines = file.readAsLinesSync();
    final patchLines = patch.split('\n');
    int applied = 0;
    int i = 0;
    while (i < patchLines.length) {
      final line = patchLines[i];
      if (line.startsWith('@@')) {
        final m = RegExp(r'@@ -(\d+)(?:,\d+)? \+(\d+)').firstMatch(line);
        if (m != null) {
          final srcStart = int.parse(m.group(1)!) - 1;
          int srcLine = srcStart;
          final hunkLines = <String>[];
          i++;
          while (i < patchLines.length && !patchLines[i].startsWith('@@') && !patchLines[i].startsWith('---') && !patchLines[i].startsWith('+++')) {
            final pl = patchLines[i];
            if (pl.startsWith('+')) {
              hunkLines.add(pl.substring(1));
            } else if (pl.startsWith('-')) {
              srcLine++;
            } else if (pl.startsWith(' ')) {
              hunkLines.add(pl.substring(1));
              srcLine++;
            }
            i++;
          }
          lines = [...lines.sublist(0, srcStart), ...hunkLines, ...lines.sublist(srcLine)];
          applied++;
          continue;
        }
      }
      i++;
    }
    await file.writeAsString(lines.join('\n'));
    return {'ok': true, 'hunks_applied': applied};
  }

  Future<Map<String, dynamic>> _readSqlite(Map<String, dynamic> args) async {
    final path = _stringArg(args, 'path');
    final query = _stringArg(args, 'query');
    final db = await openDatabase(path, readOnly: true);
    try {
      final rows = await db.rawQuery(query);
      return {'rows': rows, 'count': rows.length};
    } finally {
      await db.close();
    }
  }

  Future<Map<String, dynamic>> _readPptx(Map<String, dynamic> args) async {
    final path = _stringArg(args, 'path');
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final slideFiles = archive.files
        .where((f) => f.name.startsWith('ppt/slides/slide') && f.name.endsWith('.xml'))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final buffer = StringBuffer();
    for (final slide in slideFiles) {
      final xml = utf8.decode(slide.content as List<int>);
      final doc = XmlDocument.parse(xml);
      final texts = doc.findAllElements('a:t').map((e) => e.innerText.trim()).where((t) => t.isNotEmpty);
      if (texts.isNotEmpty) buffer.writeln(texts.join(' '));
    }
    final text = _truncate(buffer.toString(), _intArg(args, 'max_chars', 50000));
    return {'text': text, 'slides': slideFiles.length};
  }

  Future<Map<String, dynamic>> _writeDocx(Map<String, dynamic> args) async {
    final path = _stringArg(args, 'path');
    final content = _stringArg(args, 'content');
    final paragraphs = content.split('\n').map((line) {
      final escaped = line.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
      return '<w:p><w:r><w:t xml:space="preserve">$escaped</w:t></w:r></w:p>';
    }).join('');
    final docXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:body>$paragraphs<w:sectPr/></w:body></w:document>''';
    final relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';
    final contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';
    final wordRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>''';
    final archive = Archive();
    void addFile(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }
    addFile('[Content_Types].xml', contentTypesXml);
    addFile('_rels/.rels', relsXml);
    addFile('word/document.xml', docXml);
    addFile('word/_rels/document.xml.rels', wordRelsXml);
    final bytes = ZipEncoder().encode(archive)!;
    await File(path).create(recursive: true);
    await File(path).writeAsBytes(bytes);
    return {'ok': true, 'path': path};
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

  Future<Map<String, dynamic>> _readXlsx(Map<String, dynamic> args) async {
    final path = _stringArg(args, 'path');
    final maxRows = _intArg(args, 'max_rows', 200);
    final maxSheets = _intArg(args, 'max_sheets', 20);
    final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
    final sharedStrings = _readXlsxSharedStrings(archive);
    final sheets = _readXlsxSheetRefs(archive).take(maxSheets).toList();
    final resultSheets = <Map<String, dynamic>>[];

    for (final sheet in sheets) {
      final file = archive.findFile(sheet.path);
      if (file == null) continue;
      final document = XmlDocument.parse(
        utf8.decode(file.content as List<int>, allowMalformed: true),
      );
      final rows = <List<dynamic>>[];

      for (final row in document.findAllElements('row')) {
        final valuesByColumn = <int, dynamic>{};
        var maxColumn = 0;
        for (final cell in row.findElements('c')) {
          final reference = cell.getAttribute('r') ?? '';
          final columnIndex = _xlsxColumnIndex(reference);
          final value = _xlsxCellValue(cell, sharedStrings);
          valuesByColumn[columnIndex] = value;
          if (columnIndex > maxColumn) maxColumn = columnIndex;
        }
        rows.add(
          List<dynamic>.generate(
            maxColumn,
            (index) => valuesByColumn[index + 1] ?? '',
          ),
        );
        if (rows.length >= maxRows) break;
      }

      resultSheets.add({
        'name': sheet.name,
        'path': sheet.path,
        'rows': rows,
        'truncated': rows.length >= maxRows,
      });
    }

    return {
      'path': path,
      'sheets': resultSheets,
      'sheetCount': sheets.length,
    };
  }

  Future<Map<String, dynamic>> _writeXlsx(Map<String, dynamic> args) async {
    final path = _stringArg(args, 'path');
    final rawRows = args['rows'];
    if (rawRows is! List) {
      throw ArgumentError('write_xlsx requires rows: [[...], [...]]');
    }
    final sheetName = _stringArg(args, 'sheet', defaultValue: 'Sheet1');
    final rows = rawRows
        .map(
          (row) => row is List
              ? row.map((cell) => cell).toList(growable: false)
              : <dynamic>[row],
        )
        .toList(growable: false);
    final archive = Archive();

    void add(String name, String content) {
      archive.addFile(ArchiveFile.string(name, content));
    }

    add('[Content_Types].xml', _xlsxContentTypesXml);
    add('_rels/.rels', _xlsxRootRelsXml);
    add('xl/workbook.xml', _xlsxWorkbookXml(sheetName));
    add('xl/_rels/workbook.xml.rels', _xlsxWorkbookRelsXml);
    add('xl/worksheets/sheet1.xml', _xlsxWorksheetXml(rows));
    add('xl/styles.xml', _xlsxStylesXml);

    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) throw StateError('Failed to encode XLSX archive');
    await File(path).create(recursive: true);
    await File(path).writeAsBytes(encoded);
    return {
      'ok': true,
      'path': path,
      'sheet': sheetName,
      'rows': rows.length,
      'columns': rows.fold<int>(
        0,
        (maxColumns, row) => max(maxColumns, row.length),
      ),
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
    final workDir = args['working_directory']?.toString();
    final timeout = _intArg(args, 'timeout_seconds', 30);
    if (Platform.environment['PREFIX']?.contains('com.termux') == true) {
      return _termuxBridgeExec(command, workDir, timeout);
    }
    return _runCommand('/system/bin/sh', ['-c', command], args, workingDirectory: workDir);
  }

  Future<Map<String, dynamic>> _termuxBridgeExec(String command, String? workDir, int timeoutSeconds) async {
    try {
      final result = await _termuxChannel.invokeMethod<Map>('exec', {
        'command': command,
        'workDir': workDir,
        'timeout_ms': timeoutSeconds * 1000,
      });
      final r = Map<String, dynamic>.from(result ?? {});
      return {
        'exitCode': r['exitCode'] ?? -1,
        'stdout': _truncate(r['stdout']?.toString() ?? '', 20000),
        'stderr': r['stderr']?.toString() ?? '',
      };
    } catch (e) {
      return {'error': e.toString(), 'suggestion': 'Ensure Termux allow-external-apps=true in ~/.termux/termux.properties'};
    }
  }

  String _shellQuote(String s) => "'${s.replaceAll("'", "\\'\\''")}'";

  Future<Map<String, dynamic>> _writeAndRun(Map<String, dynamic> args) async {
    final path = _stringArg(args, 'path');
    await _writeFile(args);
    return _runCommand('/system/bin/sh', [path], args);
  }

  Future<Map<String, dynamic>> _termuxPython(Map<String, dynamic> args) async {
    final code = _stringArg(args, 'code');
    return _termuxBridgeExec('python -c ${_shellQuote(code)}', args['working_directory']?.toString(), _intArg(args, 'timeout_seconds', 30));
  }

  Future<Map<String, dynamic>> _termuxBash(Map<String, dynamic> args) async {
    final command = _stringArg(args, 'command');
    return _termuxBridgeExec(command, args['working_directory']?.toString(), _intArg(args, 'timeout_seconds', 30));
  }

  Future<Map<String, dynamic>> _termuxCheck(Map<String, dynamic> _) async {
    try {
      final result = await _termuxChannel.invokeMethod<Map>('check');
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      return {'termux': false, 'error': e.toString()};
    }
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

  List<String> _readXlsxSharedStrings(Archive archive) {
    final file = archive.findFile('xl/sharedStrings.xml');
    if (file == null) return const [];
    final document = XmlDocument.parse(
      utf8.decode(file.content as List<int>, allowMalformed: true),
    );
    return document.findAllElements('si').map((item) {
      return item.findAllElements('t').map((text) => text.innerText).join();
    }).toList(growable: false);
  }

  List<_XlsxSheetRef> _readXlsxSheetRefs(Archive archive) {
    final workbook = archive.findFile('xl/workbook.xml');
    if (workbook == null) return const [];
    final rels = archive.findFile('xl/_rels/workbook.xml.rels');
    final relTargets = <String, String>{};
    if (rels != null) {
      final relsDocument = XmlDocument.parse(
        utf8.decode(rels.content as List<int>, allowMalformed: true),
      );
      for (final rel in relsDocument.findAllElements('Relationship')) {
        final id = rel.getAttribute('Id');
        final target = rel.getAttribute('Target');
        if (id != null && target != null) {
          relTargets[id] = target.startsWith('/')
              ? target.substring(1)
              : p.posix.normalize('xl/$target');
        }
      }
    }

    final workbookDocument = XmlDocument.parse(
      utf8.decode(workbook.content as List<int>, allowMalformed: true),
    );
    final refs = <_XlsxSheetRef>[];
    var fallbackIndex = 1;
    for (final sheet in workbookDocument.findAllElements('sheet')) {
      final name = sheet.getAttribute('name') ?? 'Sheet$fallbackIndex';
      final relId = sheet.getAttribute('r:id');
      final target = relId == null ? null : relTargets[relId];
      refs.add(
        _XlsxSheetRef(
          name: name,
          path: target ?? 'xl/worksheets/sheet$fallbackIndex.xml',
        ),
      );
      fallbackIndex++;
    }
    return refs;
  }

  dynamic _xlsxCellValue(XmlElement cell, List<String> sharedStrings) {
    final type = cell.getAttribute('t');
    if (type == 'inlineStr') {
      return cell.findAllElements('t').map((text) => text.innerText).join();
    }
    final valueElement = cell.findElements('v').isEmpty
        ? null
        : cell.findElements('v').first;
    final raw = valueElement?.innerText ?? '';
    if (type == 's') {
      final index = int.tryParse(raw);
      if (index != null && index >= 0 && index < sharedStrings.length) {
        return sharedStrings[index];
      }
      return raw;
    }
    if (type == 'b') return raw == '1';
    if (raw.isEmpty) return '';
    return num.tryParse(raw) ?? raw;
  }

  int _xlsxColumnIndex(String reference) {
    final letters = RegExp(r'^[A-Za-z]+').stringMatch(reference) ?? 'A';
    var index = 0;
    for (final codeUnit in letters.toUpperCase().codeUnits) {
      index = index * 26 + (codeUnit - 64);
    }
    return index;
  }

  String _xlsxColumnName(int index) {
    final buffer = StringBuffer();
    while (index > 0) {
      index--;
      buffer.writeCharCode(65 + (index % 26));
      index ~/= 26;
    }
    return buffer.toString().split('').reversed.join();
  }

  String _xlsxEscape(Object? value) {
    return value
        .toString()
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  String _xlsxSheetName(String name) {
    final sanitized = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
    if (sanitized.isEmpty) return 'Sheet1';
    return sanitized.length > 31 ? sanitized.substring(0, 31) : sanitized;
  }

  String _xlsxWorkbookXml(String sheetName) {
    final safeName = _xlsxEscape(_xlsxSheetName(sheetName));
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="$safeName" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>''';
  }

  String _xlsxWorksheetXml(List<List<dynamic>> rows) {
    final rowXml = StringBuffer();
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final excelRow = rowIndex + 1;
      rowXml.write('<row r="$excelRow">');
      for (var columnIndex = 0; columnIndex < rows[rowIndex].length; columnIndex++) {
        final value = rows[rowIndex][columnIndex];
        final ref = '${_xlsxColumnName(columnIndex + 1)}$excelRow';
        if (value is num) {
          rowXml.write('<c r="$ref"><v>$value</v></c>');
        } else if (value is bool) {
          rowXml.write('<c r="$ref" t="b"><v>${value ? 1 : 0}</v></c>');
        } else if (value == null || value.toString().isEmpty) {
          rowXml.write('<c r="$ref"/>');
        } else {
          rowXml.write(
            '<c r="$ref" t="inlineStr"><is><t>${_xlsxEscape(value)}</t></is></c>',
          );
        }
      }
      rowXml.write('</row>');
    }

    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    $rowXml
  </sheetData>
</worksheet>''';
  }

  static const String _xlsxContentTypesXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>''';

  static const String _xlsxRootRelsXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''';

  static const String _xlsxWorkbookRelsXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''';

  static const String _xlsxStylesXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>
  <fills count="1"><fill><patternFill patternType="none"/></fill></fills>
  <borders count="1"><border/></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
</styleSheet>''';

  Future<Map<String, dynamic>> _ragSetEmbedModel(Map<String, dynamic> args) async {
    final path = _stringArg(args, 'path');
    final ok = await Get.find<RagService>().initEmbedModel(path);
    return {'ok': ok, 'path': path};
  }

  Future<Map<String, dynamic>> _ragIndexFile(Map<String, dynamic> args) async {
    final path = _stringArg(args, 'path');
    final f = File(path);
    if (!f.existsSync()) return {'error': 'File not found: $path'};
    final text = f.readAsStringSync();
    final n = await Get.find<RagService>().indexText(path, p.basename(path), text);
    return {'ok': true, 'chunks_indexed': n};
  }

  Future<Map<String, dynamic>> _ragIndexText(Map<String, dynamic> args) async {
    final source = _stringArg(args, 'source');
    final title = args['title']?.toString() ?? source;
    final text = _stringArg(args, 'text');
    final n = await Get.find<RagService>().indexText(source, title, text);
    return {'ok': true, 'chunks_indexed': n};
  }

  Future<Map<String, dynamic>> _ragSearch(Map<String, dynamic> args) async {
    final query = _stringArg(args, 'query');
    final k = _intArg(args, 'k', 5);
    final results = await Get.find<RagService>().search(query, k: k);
    return {'results': results, 'count': results.length};
  }

  Future<Map<String, dynamic>> _ragListSources(Map<String, dynamic> _) async {
    final sources = await Get.find<RagService>().listSources();
    return {'sources': sources, 'count': sources.length};
  }

  Future<Map<String, dynamic>> _ragStatus(Map<String, dynamic> _) async {
    final rag = Get.find<RagService>();
    final count = await rag.count();
    return {'configured': rag.isConfigured, 'total_chunks': count};
  }

  Future<Map<String, dynamic>> _ragClear(Map<String, dynamic> args) async {
    final source = args['source']?.toString();
    final rag = Get.find<RagService>();
    final deleted = source != null ? await rag.clearSource(source) : await rag.clearAll();
    return {'ok': true, 'chunks_deleted': deleted};
  }

  Future<Map<String, dynamic>> _spawnAgent(Map<String, dynamic> args) async {
    final role = args['role']?.toString() ?? 'general assistant';
    final task = args['task']?.toString() ?? '';
    final maxRounds = (args['max_rounds'] as num?)?.toInt() ?? agentMaxRounds;

    if (task.isEmpty) return {'error': 'task is required'};

    final CloudService cloud;
    try {
      cloud = Get.find<CloudService>();
    } catch (_) {
      return {'error': 'CloudService not available'};
    }
    if (!cloud.isConfigured) {
      return {'error': 'Cloud API not configured — subagents require cloud mode. Add an API key in Settings.'};
    }

    final systemPrompt = 'You are a specialized AI agent. Role: $role\n\n$protocolPrompt';
    final history = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': task},
    ];

    var response = await cloud.sendMessage(messages: history);

    for (var round = 0; round < maxRounds; round++) {
      final request = parseToolCall(response);
      if (request == null) break;

      Map<String, dynamic> toolResult;
      try {
        toolResult = await callTool(request.name, request.arguments, mode: ToolCallingMode.agent);
      } catch (e) {
        toolResult = {'error': e.toString()};
      }

      final rendered = renderToolResultForModel(request, toolResult);
      history
        ..add({'role': 'assistant', 'content': response})
        ..add({'role': 'user', 'content': rendered});

      response = await cloud.sendMessage(messages: history);
    }

    Get.find<AppLogService>().info(
      '[spawn_agent] Subagent completed',
      details: 'role=$role, rounds_used=${history.length ~/ 2}',
    );

    return {'result': response, 'role': role};
  }

  Future<Map<String, dynamic>> _getCalendarEvents(Map<String, dynamic> args) async {
    if (!Platform.isAndroid && !Platform.isIOS) return {'error': 'Calendar not available on this platform.'};
    final permission = await Permission.calendar.request();
    if (!permission.isGranted) return {'error': 'Calendar permission denied'};
    final plugin = DeviceCalendarPlugin();
    final calsResult = await plugin.retrieveCalendars();
    if (calsResult.data == null) return {'error': 'No calendars found'};
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 7));
    final end = now.add(Duration(days: _intArg(args, 'days_ahead', 30)));
    final events = <Map<String, dynamic>>[];
    for (final cal in calsResult.data!) {
      final result = await plugin.retrieveEvents(cal.id!, RetrieveEventsParams(startDate: start, endDate: end));
      for (final event in result.data ?? []) {
        events.add({'title': event.title, 'start': event.start?.toIso8601String(), 'end': event.end?.toIso8601String(), 'calendar': cal.name, 'location': event.location, 'description': event.description});
      }
    }
    events.sort((a, b) => (a['start'] ?? '').compareTo(b['start'] ?? ''));
    return {'events': events, 'count': events.length};
  }

  Future<Map<String, dynamic>> _createCalendarEvent(Map<String, dynamic> args) async {
    if (!Platform.isAndroid && !Platform.isIOS) return {'error': 'Calendar not available on this platform.'};
    final permission = await Permission.calendar.request();
    if (!permission.isGranted) return {'error': 'Calendar permission denied'};
    final plugin = DeviceCalendarPlugin();
    final calsResult = await plugin.retrieveCalendars();
    final cal = calsResult.data?.firstWhere((c) => !(c.isReadOnly ?? true), orElse: () => calsResult.data!.first);
    if (cal == null) return {'error': 'No writable calendar found'};
    final event = dc.Event(cal.id!,
      title: _stringArg(args, 'title'),
      start: tz.TZDateTime.parse(tz.getLocation('UTC'), _stringArg(args, 'start')),
      end: tz.TZDateTime.parse(tz.getLocation('UTC'), _stringArg(args, 'end')),
      description: args['description']?.toString(),
      location: args['location']?.toString(),
    );
    final result = await plugin.createOrUpdateEvent(event);
    return {'ok': result?.isSuccess == true, 'eventId': result?.data};
  }

  Future<Map<String, dynamic>> _getContacts(Map<String, dynamic> args) async {
    if (!Platform.isAndroid && !Platform.isIOS) return {'error': 'Contacts not available on this platform.'};
    final granted = await FlutterContacts.requestPermission();
    if (!granted) return {'error': 'Contacts permission denied'};
    final contacts = await FlutterContacts.getContacts(withProperties: true);
    final limit = _intArg(args, 'limit', 50);
    final mapped = contacts.take(limit).map((c) => {
      'name': c.displayName,
      'phones': c.phones.map((p) => p.number).toList(),
      'emails': c.emails.map((e) => e.address).toList(),
    }).toList();
    return {'contacts': mapped, 'count': contacts.length, 'returned': mapped.length};
  }

  Future<Map<String, dynamic>> _searchContacts(Map<String, dynamic> args) async {
    if (!Platform.isAndroid && !Platform.isIOS) return {'error': 'Contacts not available on this platform.'};
    final query = _stringArg(args, 'query').toLowerCase();
    final granted = await FlutterContacts.requestPermission();
    if (!granted) return {'error': 'Contacts permission denied'};
    final contacts = await FlutterContacts.getContacts(withProperties: true);
    final matches = contacts.where((c) =>
      c.displayName.toLowerCase().contains(query) ||
      c.phones.any((p) => p.number.contains(query)) ||
      c.emails.any((e) => e.address.toLowerCase().contains(query))
    ).take(20).map((c) => {
      'name': c.displayName,
      'phones': c.phones.map((p) => p.number).toList(),
      'emails': c.emails.map((e) => e.address).toList(),
    }).toList();
    return {'contacts': matches, 'count': matches.length};
  }

  Future<Map<String, dynamic>> _mcpAddServer(Map<String, dynamic> args) async {
    final name = _stringArg(args, 'name');
    final url = _stringArg(args, 'url');
    final auth = args['auth_header']?.toString();
    Get.find<McpService>().addServer(name, url, authHeader: auth);
    return {'ok': true, 'message': 'Server "$name" added'};
  }

  Future<Map<String, dynamic>> _mcpInitialize(Map<String, dynamic> args) async {
    final name = _stringArg(args, 'server');
    return Get.find<McpService>().initialize(name);
  }

  Future<Map<String, dynamic>> _mcpListTools(Map<String, dynamic> args) async {
    final name = _stringArg(args, 'server');
    final tools = await Get.find<McpService>().listTools(name);
    return {'tools': tools, 'count': tools.length};
  }

  Future<Map<String, dynamic>> _mcpCallTool(Map<String, dynamic> args) async {
    final server = _stringArg(args, 'server');
    final tool = _stringArg(args, 'tool');
    final toolArgs = (args['arguments'] as Map<String, dynamic>?) ?? {};
    return Get.find<McpService>().callTool(server, tool, toolArgs);
  }

  Future<Map<String, dynamic>> _mcpListServers(Map<String, dynamic> _) async {
    final servers = Get.find<McpService>().listServers();
    return {'servers': servers, 'count': servers.length};
  }

  Future<Map<String, dynamic>> _mcpRemoveServer(Map<String, dynamic> args) async {
    final name = _stringArg(args, 'server');
    Get.find<McpService>().removeServer(name);
    return {'ok': true};
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

class _XlsxSheetRef {
  const _XlsxSheetRef({required this.name, required this.path});

  final String name;
  final String path;
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
