import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ToolApprovalDialog extends StatelessWidget {
  final String toolName;
  final Map<String, dynamic> args;
  final void Function(bool approved) onResult;

  const ToolApprovalDialog({super.key, required this.toolName, required this.args, required this.onResult});

  @override
  Widget build(BuildContext context) {
    final argsPreview = args.entries.take(4).map((e) {
      final val = e.value.toString();
      return '${e.key}: ${val.length > 80 ? '${val.substring(0, 80)}\u2026' : val}';
    }).join('\n');
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.orange),
        const SizedBox(width: 8),
        const Text('Allow tool?'),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Tool: $toolName', style: const TextStyle(fontWeight: FontWeight.bold)),
        if (argsPreview.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
            child: Text(argsPreview, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          ),
        ],
      ]),
      actions: [
        TextButton(onPressed: () { Get.back(); onResult(false); }, child: const Text('Deny')),
        FilledButton(onPressed: () { Get.back(); onResult(true); }, child: const Text('Allow')),
      ],
    );
  }
}
