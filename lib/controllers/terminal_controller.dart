import 'package:flutter/services.dart';
import 'package:get/get.dart';

class TerminalEntry {
  final String command;
  final String output;
  final int exitCode;
  final DateTime time;
  final String workDir;

  const TerminalEntry({
    required this.command,
    required this.output,
    required this.exitCode,
    required this.time,
    required this.workDir,
  });
}

class TerminalController extends GetxController {
  static const _channel =
      MethodChannel('com.orailnoor.privatelm/termux_bridge');

  final entries = <TerminalEntry>[].obs;
  final isRunning = false.obs;
  final workDir = '/data/data/com.termux/files/home'.obs;

  final _history = <String>[];
  int _historyIndex = -1;

  String get prompt => 'privatelm@local:${_shortDir(workDir.value)}\$ ';

  String _shortDir(String d) {
    const home = '/data/data/com.termux/files/home';
    if (d == home) return '~';
    if (d.startsWith('$home/')) return '~/${d.substring(home.length + 1)}';
    return d;
  }

  Future<void> exec(String rawCmd) async {
    final cmd = rawCmd.trim();
    if (cmd.isEmpty) return;

    _history.remove(cmd);
    _history.add(cmd);
    _historyIndex = -1;

    if (cmd == 'clear') {
      entries.clear();
      return;
    }

    isRunning.value = true;
    final dir = workDir.value;

    try {
      // Wrap cd commands so we can track the new working directory
      final wrappedCmd = cmd.startsWith('cd ')
          ? '$cmd && pwd'
          : cmd.contains('\n')
              ? cmd
              : cmd;

      final res = await _channel.invokeMapMethod<String, dynamic>('exec', {
        'command': wrappedCmd,
        'workDir': dir,
        'timeout_ms': 60000,
      });

      final stdout = (res?['stdout'] as String? ?? '').trimRight();
      final exitCode = (res?['exitCode'] as int?) ?? -1;

      String output = stdout;
      if (cmd.startsWith('cd ') && exitCode == 0) {
        final lines = stdout.split('\n');
        final newDir = lines.last.trim();
        if (newDir.startsWith('/')) {
          workDir.value = newDir;
          output = lines.sublist(0, lines.length - 1).join('\n').trimRight();
        }
      }

      entries.add(TerminalEntry(
        command: cmd,
        output: output,
        exitCode: exitCode,
        time: DateTime.now(),
        workDir: dir,
      ));
    } catch (e) {
      entries.add(TerminalEntry(
        command: cmd,
        output: 'Error: $e',
        exitCode: -1,
        time: DateTime.now(),
        workDir: dir,
      ));
    } finally {
      isRunning.value = false;
    }
  }

  String? historyUp(String current) {
    if (_history.isEmpty) return null;
    if (_historyIndex == -1) _historyIndex = _history.length;
    if (_historyIndex > 0) {
      _historyIndex--;
      return _history[_historyIndex];
    }
    return _history.first;
  }

  String? historyDown() {
    if (_historyIndex == -1) return null;
    _historyIndex++;
    if (_historyIndex >= _history.length) {
      _historyIndex = -1;
      return '';
    }
    return _history[_historyIndex];
  }
}
