import 'context.dart';
import 'models.dart';

abstract class AiCheckRule {
  const AiCheckRule();

  void apply(AiRepoContext context, List<AiFinding> findings);
}

class LegacyAnalyzeFlagRule extends AiCheckRule {
  const LegacyAnalyzeFlagRule();

  @override
  void apply(AiRepoContext context, List<AiFinding> findings) {
    const files = <String>[
      '.github/workflows/flutter-ci.yml',
      '.windsurf/workflows/code-standardization-check.md',
      '.windsurf/workflows/development-task-closure.md',
    ];
    for (final filePath in files) {
      final snapshot = context.tryReadFile(filePath);
      if (snapshot == null) {
        continue;
      }
      for (var i = 0; i < snapshot.lines.length; i++) {
        if (!snapshot.lines[i].contains('flutter analyze --no-fatal-infos')) {
          continue;
        }
        findings.add(
          AiFinding(
            id: 'analyze.zero_warning_flag',
            severity: FindingSeverity.blocking,
            filePath: filePath,
            line: i + 1,
            message: '发现 `flutter analyze --no-fatal-infos`，与零警告门禁冲突',
          ),
        );
      }
    }
  }
}

class TtsLifecycleRule extends AiCheckRule {
  const TtsLifecycleRule();

  @override
  void apply(AiRepoContext context, List<AiFinding> findings) {
    const filePath = 'lib/features/audio/services/tts_engine_service.dart';
    _requireSnippet(
      context,
      findings,
      filePath: filePath,
      id: 'tts.dispose.progress_controller',
      snippet: '_progressController.close()',
      message: '缺少 StreamController 关闭逻辑',
    );
    _requireSnippet(
      context,
      findings,
      filePath: filePath,
      id: 'tts.dispose.audio_player',
      snippet: '_audioPlayer.dispose()',
      message: '缺少 AudioPlayer 资源释放逻辑',
    );
    _requireSnippet(
      context,
      findings,
      filePath: filePath,
      id: 'tts.dispose.fallback_engine',
      snippet: '_fallbackEngine.stop()',
      message: '缺少本地 TTS 降级引擎停止逻辑',
    );
    _requireSnippet(
      context,
      findings,
      filePath: filePath,
      id: 'tts.dispose.wakelock',
      snippet: '_wakeLock.disable()',
      message: '缺少 Wakelock 释放逻辑',
    );
  }
}

class NotifierGuardsRule extends AiCheckRule {
  const NotifierGuardsRule();

  @override
  void apply(AiRepoContext context, List<AiFinding> findings) {
    const filePath = 'lib/features/audio/providers/tts_audio_notifier.dart';
    _requireSnippet(
      context,
      findings,
      filePath: filePath,
      id: 'tts.pause_interrupt.mark',
      snippet: '_markPausedInterrupt(',
      message: '缺少暂停中断哨兵登记逻辑',
    );
    _requireSnippet(
      context,
      findings,
      filePath: filePath,
      id: 'tts.pause_interrupt.guard',
      snippet: '_isPausedInterrupt(',
      message: '缺少暂停完成回调拦截逻辑',
    );
    _requireSnippet(
      context,
      findings,
      filePath: filePath,
      id: 'tts.pause_interrupt.clear',
      snippet: '_clearPausedInterrupt(',
      message: '缺少暂停中断哨兵清理逻辑',
    );
    _requireSnippet(
      context,
      findings,
      filePath: filePath,
      id: 'tts.session_guard.playback',
      snippet: 'if (item.session != _session)',
      message: '缺少播放完成前的旧会话丢弃守卫',
    );
    _requireSnippet(
      context,
      findings,
      filePath: filePath,
      id: 'tts.session_guard.prefetch',
      snippet: 'currentSession != _session',
      message: '缺少预加载完成后的旧会话回写守卫',
    );
  }
}

class RequiredTestsRule extends AiCheckRule {
  const RequiredTestsRule();

  @override
  void apply(AiRepoContext context, List<AiFinding> findings) {
    _requireFile(
      context,
      findings,
      filePath: 'test/features/audio/tts_contract_test.dart',
      id: 'tts.contract_test',
      message: '缺少 TTS 两步下载契约测试',
    );
    _requireFile(
      context,
      findings,
      filePath: 'test/utils/test_utils.dart',
      id: 'test.shared_utils',
      message: '缺少统一测试工具基础设施',
    );
    _requireFile(
      context,
      findings,
      filePath: 'test/features/audio/tts_audio_notifier_test.dart',
      id: 'tts.notifier_regression_test',
      message: '缺少 TTS 状态机回归测试',
    );
  }
}

class IllegalConsoleOutputRule extends AiCheckRule {
  const IllegalConsoleOutputRule();

  static const Set<String> _consoleOutputAllowlist = <String>{
    'lib/core/utils/cyber_logger.dart',
  };

  @override
  void apply(AiRepoContext context, List<AiFinding> findings) {
    final debugPattern = RegExp(r'debugPrint\s*\(');
    final printPattern = RegExp(r'(^|[^A-Za-z0-9_])print\s*\(');
    for (final snapshot in context.readDartFilesUnder('lib')) {
      if (_consoleOutputAllowlist.contains(snapshot.relativePath)) {
        continue;
      }
      for (var index = 0; index < snapshot.lines.length; index++) {
        final line = snapshot.lines[index];
        final trimmed = line.trimLeft();
        if (context.isCommentLine(trimmed)) {
          continue;
        }
        if (debugPattern.hasMatch(line)) {
          findings.add(
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
          findings.add(
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
}

class HardcodedUrlRule extends AiCheckRule {
  const HardcodedUrlRule();

  @override
  void apply(AiRepoContext context, List<AiFinding> findings) {
    final urlPattern = RegExp(r'''https?://[^\s'"`]+''');
    for (final snapshot in context.readDartFilesUnder('lib')) {
      for (var index = 0; index < snapshot.lines.length; index++) {
        final line = snapshot.lines[index];
        final trimmed = line.trimLeft();
        if (context.isCommentLine(trimmed)) {
          continue;
        }
        if (!urlPattern.hasMatch(line)) {
          continue;
        }
        if (context.isAllowedUrlContext(snapshot.lines, index)) {
          continue;
        }
        findings.add(
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
}

void _requireFile(
  AiRepoContext context,
  List<AiFinding> findings, {
  required String filePath,
  required String id,
  required String message,
}) {
  final snapshot = context.tryReadFile(filePath);
  if (snapshot != null) {
    return;
  }
  findings.add(
    AiFinding(
      id: id,
      severity: FindingSeverity.blocking,
      filePath: filePath,
      message: message,
    ),
  );
}

void _requireSnippet(
  AiRepoContext context,
  List<AiFinding> findings, {
  required String filePath,
  required String id,
  required String snippet,
  required String message,
}) {
  final snapshot = context.tryReadFile(filePath);
  if (snapshot == null) {
    findings.add(
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
  findings.add(
    AiFinding(
      id: id,
      severity: FindingSeverity.blocking,
      filePath: filePath,
      message: message,
    ),
  );
}
