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
  static const _red = Color(0xFFFF5F5F);
  static const _yellow = Color(0xFFFFD060);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(child: _TerminalBody(controller: controller)),
    );
  }
}

class _TerminalBody extends StatefulWidget {
  final TerminalController controller;
  const _TerminalBody({required this.controller});

  @override
  State<_TerminalBody> createState() => _TerminalBodyState();
}

class _TerminalBodyState extends State<_TerminalBody> {
  final _inputCtrl = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollCtrl = ScrollController();

  TerminalController get ctrl => widget.controller;

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
    ctrl.exec(cmd).then((_) => _scrollToBottom());
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return;
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      final h = ctrl.historyUp(_inputCtrl.text);
      if (h != null) {
        _inputCtrl.text = h;
        _inputCtrl.selection =
            TextSelection.collapsed(offset: h.length);
      }
    } else if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      final h = ctrl.historyDown();
      if (h != null) {
        _inputCtrl.text = h;
        _inputCtrl.selection =
            TextSelection.collapsed(offset: h.length);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _buildTitleBar(),
      Expanded(
        child: GestureDetector(
          onTap: () => _focusNode.requestFocus(),
          child: Obx(() {
            final entries = ctrl.entries.toList();
            _scrollToBottom();
            return ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              itemCount: entries.length + (ctrl.isRunning.value ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == entries.length) return _buildSpinner();
                return _buildEntry(entries[i]);
              },
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
      child: Row(children: [
        const SizedBox(width: 12),
        _dot(const Color(0xFFFF5F57)),
        const SizedBox(width: 6),
        _dot(const Color(0xFFFFBD2E)),
        const SizedBox(width: 6),
        _dot(const Color(0xFF28CA41)),
        const Spacer(),
        Obx(() => Text(
              ctrl.workDir.value
                  .replaceFirst('/data/data/com.termux/files/home', '~'),
              style: GoogleFonts.sourceCodePro(
                  fontSize: 12, color: TerminalView._dim),
              overflow: TextOverflow.ellipsis,
            )),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () {
            ctrl.entries.clear();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('clear',
                style: GoogleFonts.sourceCodePro(
                    fontSize: 12, color: TerminalView._dim)),
          ),
        ),
      ]),
    );
  }

  Widget _dot(Color c) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );

  Widget _buildEntry(TerminalEntry e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Prompt + command line
        RichText(
          text: TextSpan(
            style: GoogleFonts.sourceCodePro(fontSize: 13),
            children: [
              TextSpan(
                text:
                    'privatelm@local:${_shortDir(e.workDir)}\$ ',
                style: const TextStyle(color: TerminalView._green),
              ),
              TextSpan(
                  text: e.command,
                  style: const TextStyle(color: TerminalView._white)),
            ],
          ),
        ),
        if (e.output.isNotEmpty) ...[
          const SizedBox(height: 3),
          SelectableText(
            e.output,
            style: GoogleFonts.sourceCodePro(
              fontSize: 13,
              color: e.exitCode != 0
                  ? TerminalView._red
                  : TerminalView._white,
              height: 1.5,
            ),
          ),
        ],
        if (e.exitCode != 0 && e.output.isEmpty)
          Text(
            'Exit ${ e.exitCode}',
            style: GoogleFonts.sourceCodePro(
                fontSize: 11, color: TerminalView._red),
          ),
      ]),
    );
  }

  Widget _buildSpinner() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: TerminalView._green,
          ),
        ),
        const SizedBox(width: 8),
        Text('running…',
            style: GoogleFonts.sourceCodePro(
                fontSize: 12, color: TerminalView._dim)),
      ]),
    );
  }

  Widget _buildInputBar() {
    return Obx(() {
      final prompt = ctrl.prompt;
      final running = ctrl.isRunning.value;
      return Container(
        color: const Color(0xFF111111),
        padding: EdgeInsets.only(
          left: 12,
          right: 8,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 8,
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text(prompt,
              style: GoogleFonts.sourceCodePro(
                  fontSize: 13, color: TerminalView._green)),
          Expanded(
            child: KeyboardListener(
              focusNode: FocusNode(),
              onKeyEvent: _onKey,
              child: TextField(
                controller: _inputCtrl,
                focusNode: _focusNode,
                enabled: !running,
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
                ),
              ),
            ),
          ),
          if (running)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: TerminalView._yellow),
            )
          else
            GestureDetector(
              onTap: _submit,
              child: const Icon(Icons.keyboard_return_rounded,
                  size: 18, color: TerminalView._dim),
            ),
        ]),
      );
    });
  }

  String _shortDir(String d) {
    const home = '/data/data/com.termux/files/home';
    if (d == home) return '~';
    if (d.startsWith('$home/')) return '~/${d.substring(home.length + 1)}';
    return d;
  }
}
