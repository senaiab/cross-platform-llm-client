import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class TerminalController extends GetxController {
  static const _mc =
      MethodChannel('com.orailnoor.privatelm/termux_bridge');
  static const _port = 7681;

  // Raw output buffer — UI reads outputVersion to know when to rebuild.
  final _buf = StringBuffer();
  final outputVersion = 0.obs;
  final isConnected = false.obs;
  final isStarting = false.obs;

  WebSocket? _ws;
  StreamSubscription<dynamic>? _sub;

  final _history = <String>[];
  int _histIdx = -1;

  String get rawOutput => _buf.toString();

  @override
  void onInit() {
    super.onInit();
    _launch();
  }

  @override
  void onClose() {
    _sub?.cancel();
    _ws?.close();
    super.onClose();
  }

  // ── Public API ──────────────────────────────────────────────────────────

  void send(String raw) => _ws?.add(raw);

  void sendLine(String cmd) {
    if (cmd.isNotEmpty) {
      _history.remove(cmd);
      _history.add(cmd);
      _histIdx = -1;
    }
    _ws?.add('$cmd\n');
  }

  void clearOutput() {
    _buf.clear();
    outputVersion.value++;
  }

  void sendCtrlC() => _ws?.add('\x03');
  void sendCtrlD() => _ws?.add('\x04');
  void sendCtrlL() {
    _ws?.add('\x0c');
    clearOutput();
  }

  String? historyUp() {
    if (_history.isEmpty) return null;
    if (_histIdx == -1) _histIdx = _history.length;
    if (_histIdx > 0) _histIdx--;
    return _history[_histIdx];
  }

  String? historyDown() {
    if (_histIdx == -1) return null;
    _histIdx++;
    if (_histIdx >= _history.length) {
      _histIdx = -1;
      return '';
    }
    return _history[_histIdx];
  }

  Future<void> reconnect() async {
    _sub?.cancel();
    await _ws?.close();
    isConnected.value = false;
    _buf.write('\r\n[Reconnecting…]\r\n');
    outputVersion.value++;
    await _startBridge();
    await _connect();
  }

  // ── Internal ─────────────────────────────────────────────────────────────

  Future<void> _launch() async {
    isStarting.value = true;
    await _deployScript();
    await _startBridge();
    await _connect();
    isStarting.value = false;
  }

  Future<void> _deployScript() async {
    try {
      final src =
          await rootBundle.loadString('assets/terminal_bridge.py');
      final dest = File(
          '/data/data/com.termux/files/home/.privatelm_bridge.py');
      await dest.writeAsString(src);
    } catch (e) {
      _append('[deploy error] $e\r\n');
    }
  }

  Future<void> _startBridge() async {
    try {
      await _mc.invokeMethod<dynamic>('exec', {
        'command': 'pkill -f .privatelm_bridge.py 2>/dev/null; sleep 0.3; '
            'nohup python3 ~/.privatelm_bridge.py '
            '> ~/.privatelm_bridge.log 2>&1 &',
        'timeout_ms': 5000,
      });
    } catch (_) {}
  }

  Future<void> _connect() async {
    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 400));
      try {
        final ws = await WebSocket.connect('ws://127.0.0.1:$_port')
            .timeout(const Duration(seconds: 2));
        _ws = ws;
        _sub = ws.listen(
          (data) => _append(data as String),
          onDone: () {
            isConnected.value = false;
            _append('\r\n[disconnected — tap Reconnect]\r\n');
          },
          onError: (_) => isConnected.value = false,
          cancelOnError: false,
        );
        isConnected.value = true;
        return;
      } catch (_) {}
    }
    _append(
      '\r\n[ERROR] Could not start terminal bridge.\r\n'
      'Ensure python3 is installed: pkg install python\r\n',
    );
    outputVersion.value++;
  }

  void _append(String s) {
    _buf.write(s);
    outputVersion.value++;
  }
}
