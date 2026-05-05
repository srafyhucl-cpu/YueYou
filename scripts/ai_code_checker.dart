import 'dart:io';

enum FindingSeverity { blocking, warning }

class AiFinding {
  const AiFinding({
    required this.id,
    required this.severity,
    required this.filePath,
    required this.message,
    this.line,
  });

  final String id;
  final FindingSeverity severity;
  final String filePath;
  final String message;
  final int? line;

  String format() {
    final severityLabel =
        severity == FindingSeverity.blocking ? 'BLOCKING' : 'WARNING';
    final lineSuffix = line == null ? '' : ':$line';
    return '[AI-CHECK][$severityLabel][$id] $filePath$lineSuffix $message';
  }
}

class FileSnapshot {
  FileSnapshot({
    required this.relativePath,
    required this.content,
  }) : lines = content.split('\n');

  final String relativePath;
  final String content;
  final List<String> lines;
}

class AiCheckSummary {
  const AiCheckSummary({
    required this.blockingCount,
    required this.warningCount,
  });

  final int blockingCount;
  final int warningCount;

  bool get hasBlocking => blockingCount > 0;
}

class AiCodeChecker {
  AiCodeChecker(this.repoRoot);

  static const Set<String> _consoleOutputAllowlist = <String>{
    'lib/core/utils/cyber_logger.dart',
  };

  final Directory repoRoot;
  final List<AiFinding> _findings = <AiFinding>[];

  AiCheckSummary run() {
    _checkLegacyAnalyzeFlag();
    _checkTtsLifecycle();
    _checkNotifierGuards();
    _checkRequiredTests();
    _checkIllegalConsoleOutput();
    _checkHardcodedUrls();
    _printFindings();

    final blockingCount = _findings
        .where((finding) => finding.severity == FindingSeverity.blocking)
        .length;
    final warningCount = _findings
        .where((finding) => finding.severity == FindingSeverity.warning)
        .length;

    return AiCheckSummary(
      blockingCount: blockingCount,
      warningCount: warningCount,
    );
  }

  void _checkLegacyAnalyzeFlag() {
    const files = <String>[
      '.github/workflows/flutter-ci.yml',
      '.windsurf/workflows/code-standardization-check.md',
      '.windsurf/workflows/development-task-closure.md',
    ];
    for (final filePath in files) {
      final snapshot = _tryReadFile(filePath);
      if (snapshot == null) {
        continue;
      }
      final index = snapshot.lines.indexWhere(
        (line) => line.contains('flutter analyze --no-fatal-infos'),
      );
      if (index == -1) {
        continue;
      }
      _findings.add(
        AiFinding(
          id: 'analyze.zero_warning_flag',
          severity: FindingSeverity.blocking,
          filePath: filePath,
          line: index + 1,
          message: '发现 `flutter analyze --no-fatal-infos`，与零警告门禁冲突',
        ),
      );
    }
  }

  void _checkTtsLifecycle() {
    const filePath = 'lib/features/audio/services/tts_engine_service.dart';
    _requireSnippet(
      filePath: filePath,
      id: 'tts.dispose.progress_controller',
      snippet: '_progressController.close()',
      message: '缺少 StreamController 关闭逻辑',
    );
    _requireSnippet(
      filePath: filePath,
      id: 'tts.dispose.audio_player',
      snippet: '_audioPlayer.dispose()',
      message: '缺少 AudioPlayer 资源释放逻辑',
    );
    _requireSnippet(
      filePath: filePath,
      id: 'tts.dispose.fallback_engine',
      snippet: '_fallbackEngine.stop()',
      message: '缺少本地 TTS 降级引擎停止逻辑',
    );
    _requireSnippet(
      filePath: filePath,
      id: 'tts.dispose.wakelock',
      snippet: '_wakeLock.disable()',
      message: '缺少 Wakelock 释放逻辑',
    );
  }

  void _checkNotifierGuards() {
    const filePath = 'lib/features/audio/providers/tts_audio_notifier.dart';
    _requireSnippet(
      filePath: filePath,
      id: 'tts.pause_interrupt.mark',
      snippet: '_markPausedInterrupt(',
      message: '缺少暂停中断哨兵登记逻辑',
    );
    _requireSnippet(
      filePath: filePath,
      id: 'tts.pause_interrupt.guard',
      snippet: '_isPausedInterrupt(',
      message: '缺少暂停完成回调拦截逻辑',
    );
    _requireSnippet(
      filePath: filePath,
      id: 'tts.pause_interrupt.clear',
      snippet: '_clearPausedInterrupt(',
      message: '缺少暂停中断哨兵清理逻辑',
    );
    _requireSnippet(
      filePath: filePath,
      id: 'tts.session_guard.playback',
      snippet: 'if (item.session != _session)',
      message: '缺少播放完成前的旧会话丢弃守卫',
    );
    _requireSnippet(
      filePath: filePath,
      id: 'tts.session_guard.prefetch',
      snippet: 'currentSession != _session',
      message: '缺少预加载完成后的旧会话回写守卫',
    );
  }

  void _checkRequiredTests() {
    _requireFile(
      filePath: 'test/features/audio/tts_contract_test.dart',
      id: 'tts.contract_test',
      message: '缺少 TTS 两步下载契约测试',
    );
    _requireFile(
      filePath: 'test/utils/test_utils.dart',
      id: 'test.shared_utils',
      message: '缺少统一测试工具基础设施',
    );
    _requireFile(
      filePath: 'test/features/audio/tts_audio_notifier_test.dart',
      id: 'tts.notifier_regression_test',
      message: '缺少 TTS 状态机回归测试',
    );
  }

  void _checkIllegalConsoleOutput() {
    final debugPattern = RegExp(r'debugPrint\s*\(');
    final printPattern = RegExp(r'(^|[^A-Za-z0-9_])print\s*\(');
    for (final snapshot in _readDartFilesUnder('lib')) {
      if (_consoleOutputAllowlist.contains(snapshot.relativePath)) {
        continue;
      }
      for (var index = 0; index < snapshot.lines.length; index++) {
        final line = snapshot.lines[index];
        final trimmed = line.trimLeft();
        if (_isCommentLine(trimmed)) {
          continue;
        }
        if (debugPattern.hasMatch(line)) {
          _findings.add(
            AiFinding(
              id: 'console.debug_print',
              severity: FindingSeverity.blocking,
              filePath: snapshot.relativePath,
              line: index + 1,
              message: '业务代码中禁止使用 debugPrint()',
            ),
          );
        }
        if (printPattern.hasMatch(line)) {
          _findings.add(
            AiFinding(
              id: 'console.print',
              severity: FindingSeverity.blocking,
              filePath: snapshot.relativePath,
              line: index + 1,
              message: '业务代码中禁止直接使用 print()',
            ),
          );
        }
      }
    }
  }

  void _checkHardcodedUrls() {
    final urlPattern = RegExp(r'''https?://[^\s'"`]+''');
    for (final snapshot in _readDartFilesUnder('lib')) {
      for (var index = 0; index < snapshot.lines.length; index++) {
        final line = snapshot.lines[index];
        final trimmed = line.trimLeft();
        if (_isCommentLine(trimmed)) {
          continue;
        }
        if (!urlPattern.hasMatch(line)) {
          continue;
        }
        if (_isAllowedUrlContext(snapshot.lines, index)) {
          continue;
        }
        _findings.add(
          AiFinding(
            id: 'config.hardcoded_url',
            severity: FindingSeverity.warning,
            filePath: snapshot.relativePath,
            line: index + 1,
            message: '发现疑似硬编码 URL，请确认是否应改为环境变量或配置常量',
          ),
        );
      }
    }
  }

  void _requireFile({
    required String filePath,
    required String id,
    required String message,
  }) {
    final file = File(_absolutePath(filePath));
    if (file.existsSync()) {
      return;
    }
    _findings.add(
      AiFinding(
        id: id,
        severity: FindingSeverity.blocking,
        filePath: filePath,
        message: message,
      ),
    );
  }

  void _requireSnippet({
    required String filePath,
    required String id,
    required String snippet,
    required String message,
  }) {
    final snapshot = _tryReadFile(filePath);
    if (snapshot == null) {
      _findings.add(
        AiFinding(
          id: id,
          severity: FindingSeverity.blocking,
          filePath: filePath,
          message: '目标文件不存在，无法执行检查',
        ),
      );
      return;
    }
    if (snapshot.content.contains(snippet)) {
      return;
    }
    _findings.add(
      AiFinding(
        id: id,
        severity: FindingSeverity.blocking,
        filePath: filePath,
        message: message,
      ),
    );
  }

  Iterable<FileSnapshot> _readDartFilesUnder(String directoryPath) sync* {
    final dir = Directory(_absolutePath(directoryPath));
    if (!dir.existsSync()) {
      return;
    }
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final relativePath = _relativePath(entity.path);
      yield FileSnapshot(
        relativePath: relativePath,
        content: entity.readAsStringSync(),
      );
    }
  }

  FileSnapshot? _tryReadFile(String relativePath) {
    final file = File(_absolutePath(relativePath));
    if (!file.existsSync()) {
      return null;
    }
    return FileSnapshot(
      relativePath: relativePath,
      content: file.readAsStringSync(),
    );
  }

  bool _isAllowedUrlContext(List<String> lines, int index) {
    final start = index - 4 < 0 ? 0 : index - 4;
    final end = index + 1 >= lines.length ? lines.length - 1 : index + 1;
    final window = lines.sublist(start, end + 1).join('\n');
    return window.contains('String.fromEnvironment(');
  }

  bool _isCommentLine(String trimmedLine) {
    return trimmedLine.startsWith('//') ||
        trimmedLine.startsWith('/*') ||
        trimmedLine.startsWith('*') ||
        trimmedLine.startsWith('///');
  }

  String _absolutePath(String relativePath) {
    final normalized = relativePath.replaceAll('/', Platform.pathSeparator);
    return '${repoRoot.path}${Platform.pathSeparator}$normalized';
  }

  String _relativePath(String absolutePath) {
    final normalizedAbsolute = absolutePath.replaceAll('\\', '/');
    final normalizedRoot = repoRoot.absolute.path.replaceAll('\\', '/');
    if (!normalizedAbsolute.startsWith(normalizedRoot)) {
      return normalizedAbsolute;
    }
    final relative = normalizedAbsolute.substring(normalizedRoot.length + 1);
    return relative;
  }

  void _printFindings() {
    stdout.writeln('🔍 开始 AI 工程门禁检查...');
    if (_findings.isEmpty) {
      stdout.writeln('✅ AI 工程门禁检查通过');
      return;
    }
    for (final finding in _findings) {
      stdout.writeln(finding.format());
    }
  }
}

void main() {
  final checker = AiCodeChecker(Directory.current);
  final summary = checker.run();
  stdout.writeln(
    '📊 AI 工程门禁结果：阻断 ${summary.blockingCount} 项，警告 ${summary.warningCount} 项',
  );
  if (summary.hasBlocking) {
    stderr.writeln('❌ AI 工程门禁未通过');
    exitCode = 1;
    return;
  }
  stdout.writeln('✅ AI 工程门禁已通过');
}
