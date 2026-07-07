import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/terminal_controller.dart';

class TerminalView extends GetView<TerminalController> {
  const TerminalView({super.key});

  static const _bg = Color(0xFF0D0D0D);
  static const _green = Color(0xFF4AFF91);
  static const _dim = Color(0xFF6B6B6B);
  static const _white = Color(0xFFE8E8E8);
  static const _yellow = Color(0xFFFFD060);
  static const _red = Color(0xFFFF5F5F);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(child: _TerminalBody(ctrl: controller)),
    );
  }
}

class _TerminalBody extends StatefulWidget {
  final TerminalController ctrl;
  const _TerminalBody({required this.ctrl});

  @override
  State<_TerminalBody> createState() => _TerminalBodyState();
}

class _TerminalBodyState extends State<_TerminalBody> {
  final _inputCtrl = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollCtrl = ScrollController();

  TerminalController get ctrl => widget.ctrl;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _focusNode.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final cmd = _inputCtrl.text;
    _inputCtrl.clear();
    ctrl.sendLine(cmd);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        final h = ctrl.historyUp();
        if (h != null) {
          _inputCtrl.text = h;
          _inputCtrl.selection =
              TextSelection.collapsed(offset: h.length);
        }
      case LogicalKeyboardKey.arrowDown:
        final h = ctrl.historyDown();
        if (h != null) {
          _inputCtrl.text = h;
          _inputCtrl.selection =
              TextSelection.collapsed(offset: h.length);
        }
    }
  }

  // Strip ANSI escape sequences and normalize line endings for display.
  static final _ansiRe = RegExp(
    r'\x1B(?:'
    r'\[[0-?]*[ -/]*[@-~]'  // CSI sequences (colors, cursor, erase…)
    r'|[PX^_].*?\x1B\\'     // DCS / SOS / PM / APC (string terminator)
    r'|[()].'               // Character set designations
    r'|[^@-Z\\-_]'         // Other two-char ESC sequences
    r')',
  );

  String _render(String raw) {
    final noAnsi = raw.replaceAll(_ansiRe, '');
    // Handle \r: treat each \n-delimited line, take last segment after \r
    final lines = noAnsi.split('\n');
    return lines.map((l) {
      final parts = l.split('\r');
      return parts.last;
    }).join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _buildTitleBar(),
      Expanded(
        child: GestureDetector(
          onTap: () => _focusNode.requestFocus(),
          child: Obx(() {
            // Read outputVersion to subscribe to updates.
            ctrl.outputVersion.value;
            final text = _render(ctrl.rawOutput);
            _scrollToBottom();
            return ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              children: [
                SelectableText(
                  text,
                  style: GoogleFonts.sourceCodePro(
                    fontSize: 13,
                    color: TerminalView._white,
                    height: 1.5,
                  ),
                ),
              ],
            );
          }),
        ),
      ),
      _buildInputBar(),
    ]);
  }

  Widget _buildTitleBar() {
    return Container(
      height: 44,
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        _dot(const Color(0xFFFF5F57)),
        const SizedBox(width: 6),
        _dot(const Color(0xFFFFBD2E)),
        const SizedBox(width: 6),
        _dot(const Color(0xFF28CA41)),
        const SizedBox(width: 12),
        Obx(() {
          final connected = ctrl.isConnected.value;
          final starting = ctrl.isStarting.value;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: starting
                    ? TerminalView._yellow
                    : connected
                        ? TerminalView._green
                        : TerminalView._red,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              starting
                  ? 'starting…'
                  : connected
                      ? 'bash  ·  interactive PTY'
                      : 'disconnected',
              style: GoogleFonts.sourceCodePro(
                  fontSize: 12, color: TerminalView._dim),
            ),
          ]);
        }),
        const Spacer(),
        // Ctrl+C button
        _iconBtn(Icons.stop_circle_outlined, TerminalView._red,
            ctrl.sendCtrlC),
        // Clear button
        _iconBtn(Icons.cleaning_services_outlined, TerminalView._dim,
            ctrl.clearOutput),
        // Reconnect button
        Obx(() => ctrl.isConnected.value
            ? const SizedBox.shrink()
            : _iconBtn(Icons.refresh_rounded, TerminalView._yellow,
                ctrl.reconnect)),
      ]),
    );
  }

  Widget _dot(Color c) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );

  Widget _iconBtn(IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(icon, size: 18, color: color),
        ),
      );

  Widget _buildInputBar() {
    return Obx(() {
      final connected = ctrl.isConnected.value;
      final starting = ctrl.isStarting.value;
      return Container(
        color: const Color(0xFF111111),
        padding: EdgeInsets.only(
          left: 12,
          right: 8,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 8,
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text(
            r'$ ',
            style: GoogleFonts.sourceCodePro(
                fontSize: 13, color: TerminalView._green),
          ),
          Expanded(
            child: KeyboardListener(
              focusNode: FocusNode(),
              onKeyEvent: _onKey,
              child: TextField(
                controller: _inputCtrl,
                focusNode: _focusNode,
                enabled: connected && !starting,
                autofocus: false,
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
                style: GoogleFonts.sourceCodePro(
                    fontSize: 13, color: TerminalView._white),
                cursorColor: TerminalView._green,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'type a command…',
                  hintStyle: TextStyle(color: TerminalView._dim),
                ),
              ),
            ),
          ),
          if (starting)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: TerminalView._yellow),
            )
          else if (connected)
            GestureDetector(
              onTap: _submit,
              child: const Icon(Icons.keyboard_return_rounded,
                  size: 18, color: TerminalView._dim),
            )
          else
            GestureDetector(
              onTap: ctrl.reconnect,
              child: const Icon(Icons.refresh_rounded,
                  size: 18, color: TerminalView._yellow),
            ),
        ]),
      );
    });
  }
}
