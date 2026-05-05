import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/ai_code_checker.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ai_code_checker_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AiCodeChecker', () {
    test('在基线工程结构完整时返回全绿结果', () {
      _createBaselineRepo(tempDir);

      final checker = AiCodeChecker(tempDir);
      final summary = checker.run();

      expect(summary.blockingCount, 0);
      expect(summary.warningCount, 0);
      expect(checker.findings, isEmpty);
    });

    test('命中零警告冲突与资源释放缺失时返回阻断项', () {
      _createBaselineRepo(
        tempDir,
        includeLegacyAnalyzeFlag: true,
        includeWakeLockDispose: false,
      );

      final checker = AiCodeChecker(tempDir);
      final summary = checker.run();
      final findingIds = checker.findings.map((item) => item.id).toList();

      expect(summary.blockingCount, 4);
      expect(findingIds, contains('analyze.zero_warning_flag'));
      expect(findingIds, contains('tts.dispose.wakelock'));
    });

    test('对白名单外的 debugPrint 与硬编码 URL 分别输出阻断和警告', () {
      _createBaselineRepo(
        tempDir,
        includeBusinessDebugPrint: true,
        includeHardcodedUrl: true,
      );

      final checker = AiCodeChecker(tempDir);
      final summary = checker.run();
      final findingIds = checker.findings.map((item) => item.id).toList();
      final findingPaths =
          checker.findings.map((item) => item.filePath).toList();

      expect(summary.blockingCount, 1);
      expect(summary.warningCount, 1);
      expect(findingIds, contains('console.debug_print'));
      expect(findingIds, contains('config.hardcoded_url'));
      expect(findingPaths, isNot(contains('lib/core/utils/cyber_logger.dart')));
    });

    test('同一实例重复运行时不会累计旧 findings', () {
      _createBaselineRepo(
        tempDir,
        includeLegacyAnalyzeFlag: true,
      );

      final checker = AiCodeChecker(tempDir);
      final firstSummary = checker.run();

      expect(firstSummary.blockingCount, 3);
      expect(checker.findings.map((item) => item.id),
          contains('analyze.zero_warning_flag'));

      _writeFile(
        tempDir,
        '.github/workflows/flutter-ci.yml',
        'name: ci\nrun: flutter analyze\n',
      );
      _writeFile(
        tempDir,
        '.windsurf/workflows/code-standardization-check.md',
        '```bash\nflutter analyze\n```\n',
      );
      _writeFile(
        tempDir,
        '.windsurf/workflows/development-task-closure.md',
        '```bash\nflutter analyze\n```\n',
      );

      final secondSummary = checker.run();

      expect(secondSummary.blockingCount, 0);
      expect(secondSummary.warningCount, 0);
      expect(checker.findings, isEmpty);
    });
  });
}

void _createBaselineRepo(
  Directory root, {
  bool includeLegacyAnalyzeFlag = false,
  bool includeWakeLockDispose = true,
  bool includeBusinessDebugPrint = false,
  bool includeHardcodedUrl = false,
}) {
  final analyzeCommand = includeLegacyAnalyzeFlag
      ? 'flutter analyze --no-fatal-infos'
      : 'flutter analyze';
  final wakeLockSnippet = includeWakeLockDispose ? '_wakeLock.disable();' : '';

  _writeFile(
    root,
    '.github/workflows/flutter-ci.yml',
    'name: ci\nrun: $analyzeCommand\n',
  );
  _writeFile(
    root,
    '.windsurf/workflows/code-standardization-check.md',
    '```bash\n$analyzeCommand\n```\n',
  );
  _writeFile(
    root,
    '.windsurf/workflows/development-task-closure.md',
    '```bash\n$analyzeCommand\n```\n',
  );
  _writeFile(
    root,
    'lib/features/audio/services/tts_engine_service.dart',
    '''
class TtsEngineService {
  void dispose() {
    _progressController.close();
    _audioPlayer.dispose();
    _fallbackEngine.stop();
    $wakeLockSnippet
  }
}
''',
  );
  _writeFile(
    root,
    'lib/features/audio/providers/tts_audio_notifier.dart',
    '''
class TtsAudioNotifier {
  void pause() {
    _markPausedInterrupt(_currentItem);
    _clearPausedInterrupt();
  }

  void play() {
    if (item.session != _session) {}
    if (currentSession != _session) {}
    _isPausedInterrupt(item);
  }
}
''',
  );
  _writeFile(
    root,
    'lib/core/utils/cyber_logger.dart',
    '''
void logReady() {
  debugPrint('allowed');
}
''',
  );
  _writeFile(
    root,
    'lib/core/config/app_info_config.dart',
    '''
class AppInfoConfig {
  static const String marketDownloadUrl = String.fromEnvironment(
    'MARKET_DOWNLOAD_URL',
    defaultValue: 'https://play.google.com/store/apps/details?id=com.yueyou.app',
  );
}
''',
  );

  if (includeBusinessDebugPrint || includeHardcodedUrl) {
    final buffer = StringBuffer()
      ..writeln('class DemoScreen {')
      ..writeln('  void act() {');
    if (includeBusinessDebugPrint) {
      buffer.writeln("    debugPrint('bad');");
    }
    if (includeHardcodedUrl) {
      buffer.writeln("    final url = 'https://example.com/api';");
    }
    buffer
      ..writeln('  }')
      ..writeln('}');
    _writeFile(
      root,
      'lib/features/demo/presentation/demo_screen.dart',
      buffer.toString(),
    );
  }

  _writeFile(
      root, 'test/features/audio/tts_contract_test.dart', 'void main() {}\n');
  _writeFile(root, 'test/features/audio/tts_audio_notifier_test.dart',
      'void main() {}\n');
  _writeFile(root, 'test/utils/test_utils.dart', 'void main() {}\n');
}

void _writeFile(Directory root, String relativePath, String content) {
  final normalized = relativePath.replaceAll('/', Platform.pathSeparator);
  final file = File('${root.path}${Platform.pathSeparator}$normalized');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}
