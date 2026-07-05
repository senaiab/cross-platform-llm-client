// Pure static utility class for reasoning features.
// No GetX service needed — import and call statically.

enum TaskMode { general, debug, coding, android, terminal, business, research, document }

class ReasoningService {
  ReasoningService._();

  // ─── Mode Detection ────────────────────────────────────────────────────────

  static TaskMode detectMode(String text) {
    final lower = text.toLowerCase();

    // Debug
    if (lower.contains('error') ||
        lower.contains('crash') ||
        lower.contains('stack trace') ||
        lower.contains('exception') ||
        lower.contains('bug') ||
        lower.contains('fix') ||
        lower.contains('not working') ||
        lower.contains('broken') ||
        lower.contains('fail') ||
        lower.contains('debug')) {
      return TaskMode.debug;
    }

    // Android
    if (lower.contains('android') ||
        lower.contains('gradle') ||
        lower.contains('manifest') ||
        lower.contains('apk') ||
        lower.contains('adb') ||
        lower.contains('kotlin') ||
        lower.contains('java') ||
        lower.contains('sdk') ||
        lower.contains('flutter') ||
        lower.contains('build.gradle') ||
        lower.contains('androidmanifest')) {
      return TaskMode.android;
    }

    // Terminal
    if (lower.contains('command') ||
        lower.contains('terminal') ||
        lower.contains('shell') ||
        lower.contains('bash') ||
        lower.contains('run ') ||
        lower.contains('install ') ||
        lower.contains('chmod') ||
        lower.contains('sudo') ||
        lower.contains('apt') ||
        lower.contains('pip ') ||
        lower.contains('npm ') ||
        lower.contains('git ')) {
      return TaskMode.terminal;
    }

    // Coding
    if (lower.contains('code') ||
        lower.contains('function') ||
        lower.contains('class') ||
        lower.contains('implement') ||
        lower.contains('write a') ||
        lower.contains('create a') ||
        lower.contains('algorithm') ||
        lower.contains('dart') ||
        lower.contains('python') ||
        lower.contains('javascript') ||
        lower.contains('typescript') ||
        lower.contains('api') ||
        lower.contains('library') ||
        lower.contains('refactor')) {
      return TaskMode.coding;
    }

    // Research
    if (lower.contains('research') ||
        lower.contains('analyze') ||
        lower.contains('compare') ||
        lower.contains('difference') ||
        lower.contains('explain') ||
        lower.contains('what is') ||
        lower.contains('how does') ||
        lower.contains('why does') ||
        lower.contains('overview') ||
        lower.contains('summary of')) {
      return TaskMode.research;
    }

    // Document
    if (lower.contains('write') ||
        lower.contains('draft') ||
        lower.contains('document') ||
        lower.contains('report') ||
        lower.contains('email') ||
        lower.contains('letter') ||
        lower.contains('proposal') ||
        lower.contains('template') ||
        lower.contains('format')) {
      return TaskMode.document;
    }

    // Business
    if (lower.contains('business') ||
        lower.contains('strategy') ||
        lower.contains('plan') ||
        lower.contains('revenue') ||
        lower.contains('customer') ||
        lower.contains('market') ||
        lower.contains('roi') ||
        lower.contains('invoice') ||
        lower.contains('pricing') ||
        lower.contains('sales')) {
      return TaskMode.business;
    }

    return TaskMode.general;
  }

  // ─── Mode Name ─────────────────────────────────────────────────────────────

  static String modeName(TaskMode mode) {
    switch (mode) {
      case TaskMode.general:
        return 'General';
      case TaskMode.debug:
        return 'Debug';
      case TaskMode.coding:
        return 'Coding';
      case TaskMode.android:
        return 'Android';
      case TaskMode.terminal:
        return 'Terminal';
      case TaskMode.business:
        return 'Business';
      case TaskMode.research:
        return 'Research';
      case TaskMode.document:
        return 'Document';
    }
  }

  // ─── Mode-Specific System Additions ────────────────────────────────────────

  static String systemAdditionForMode(TaskMode mode) {
    switch (mode) {
      case TaskMode.general:
        return '';
      case TaskMode.debug:
        return 'Find root cause → exact fix → verification command';
      case TaskMode.coding:
        return 'Give file-by-file implementation steps with exact file names';
      case TaskMode.android:
        return 'Focus on Gradle, SDK, AndroidManifest.xml, Kotlin/Java, dependencies, permissions, build logs';
      case TaskMode.terminal:
        return 'Give exact commands only, in safe order';
      case TaskMode.business:
        return 'Professional structure, clear recommendations, next steps';
      case TaskMode.research:
        return 'Separate facts/assumptions/unknowns/recommendations';
      case TaskMode.document:
        return 'Clean, professional, ready-to-use text';
    }
  }

  // ─── Quality Checklist ─────────────────────────────────────────────────────

  static const String qualityChecklist = '''
Before responding, verify:
- Is the answer specific and actionable (not vague)?
- Does it directly address the user's question?
- Are all claims accurate to the best of your knowledge?
- Is the response complete — not cut off or partial?''';

  // ─── Weak Answer Detection ─────────────────────────────────────────────────

  static bool isWeakAnswer(String answer) {
    if (answer.trim().length < 100) return true;
    final lower = answer.toLowerCase();
    final weakPhrases = [
      "i don't know",
      "i do not know",
      "as an ai",
      "as an artificial intelligence",
      "unable to",
      "i cannot",
      "i can't",
      "i'm not able",
      "i am not able",
      "i'm unable",
      "i am unable",
      "i don't have access",
      "i do not have access",
      "i'm not sure",
      "i am not sure",
      "sorry, i",
      "i apologize",
    ];
    return weakPhrases.any((phrase) => lower.contains(phrase));
  }

  // ─── Escalation Prompt ─────────────────────────────────────────────────────

  static String escalationPrefix(String weakAnswer) {
    return 'Your previous response was incomplete or too vague. '
        'Please provide a more specific and detailed answer. '
        'Be concrete, give exact steps or examples, and fully address the question.';
  }

  // ─── Planner / Worker / Checker Instructions ───────────────────────────────

  static const String plannerInstruction =
      'You are a Planner. Analyze the user\'s request carefully. '
      'Identify the key sub-tasks, potential challenges, and the best approach. '
      'Output a concise numbered plan (no final answer yet). '
      'Do NOT solve the problem — only plan the steps to solve it.';

  static String workerInstruction(String plan) =>
      'You are a Worker. Use the following plan to solve the user\'s request:\n\n'
      '$plan\n\n'
      'Execute the plan fully and give a complete, detailed answer.';

  static String checkerInstruction(String draft) =>
      'You are a Checker. Review the following draft answer for correctness, '
      'completeness, and clarity:\n\n'
      '$draft\n\n'
      'If the draft is correct and complete, output it as-is. '
      'If there are errors or gaps, correct them and output the improved answer. '
      'Output only the final answer — no meta-commentary.';
}
