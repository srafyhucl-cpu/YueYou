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

    test('非豁免 service 文件超过警戒线时输出 warning（不阻断）', () {
      _createBaselineRepo(tempDir);
      _writeFile(
        tempDir,
        'lib/features/sample/services/sample_service.dart',
        _generateDartFileContent(lines: 650, publicClassName: 'SampleService'),
      );

      final checker = AiCodeChecker(tempDir);
      final summary = checker.run();
      final ids = checker.findings.map((f) => f.id).toList();

      expect(summary.blockingCount, 0);
      expect(ids, contains('file_size.exceeds_warning'));
    });

    test('非豁免 service 文件超过硬上限时输出 blocking', () {
      _createBaselineRepo(tempDir);
      _writeFile(
        tempDir,
        'lib/features/sample/services/sample_service.dart',
        _generateDartFileContent(lines: 850, publicClassName: 'SampleService'),
      );

      final checker = AiCodeChecker(tempDir);
      final summary = checker.run();
      final blockingIds = checker.findings
          .where((f) => f.severity == FindingSeverity.blocking)
          .map((f) => f.id)
          .toList();

      expect(summary.blockingCount, greaterThanOrEqualTo(1));
      expect(blockingIds, contains('file_size.exceeds_blocking'));
    });

    test('豁免名单内的 tts_engine_service 超硬上限时降级为 warning', () {
      _createBaselineRepo(tempDir);
      // 重写豁免路径文件，使其超过 services 硬上限。
      _writeFile(
        tempDir,
        'lib/features/audio/services/tts_engine_service.dart',
        _generateBigTtsEngineService(lines: 1500),
      );

      final checker = AiCodeChecker(tempDir);
      final summary = checker.run();
      final findingsForFile = checker.findings
          .where((f) =>
              f.filePath ==
              'lib/features/audio/services/tts_engine_service.dart')
          .toList();

      expect(
        findingsForFile.any((f) =>
            f.id == 'file_size.exceeds_blocking' &&
            f.severity == FindingSeverity.warning),
        isTrue,
        reason: '豁免名单内的文件 blocking 必须降级为 warning',
      );
      expect(summary.blockingCount, 0);
    });

    test('非豁免文件公开类数量超过上限时输出 blocking', () {
      _createBaselineRepo(tempDir);
      _writeFile(
        tempDir,
        'lib/features/sample/services/many_class_service.dart',
        '''
class FirstService {}
class SecondService {}
class ThirdService {}
class FourthService {}
''',
      );

      final checker = AiCodeChecker(tempDir);
      checker.run();
      final findings = checker.findings
          .where((f) => f.id == 'file_size.too_many_public_classes')
          .toList();

      expect(findings, hasLength(1));
      expect(findings.first.severity, FindingSeverity.blocking);
      expect(findings.first.filePath,
          'lib/features/sample/services/many_class_service.dart');
    });

    test('使用 part 指令规避行数门禁时输出 blocking', () {
      _createBaselineRepo(tempDir);
      _writeFile(
        tempDir,
        'lib/features/sample/services/part_using_service.dart',
        '''
library sample;

part 'sample_part.dart';

class SampleService {}
''',
      );
      _writeFile(
        tempDir,
        'lib/features/sample/services/sample_part.dart',
        '''
part of 'part_using_service.dart';

class SampleHelper {}
''',
      );

      final checker = AiCodeChecker(tempDir);
      checker.run();
      final partFindings = checker.findings
          .where((f) => f.id == 'file_size.part_directive')
          .toList();

      expect(partFindings.length, greaterThanOrEqualTo(2),
          reason: 'part 与 part of 都应被检测');
      for (final f in partFindings) {
        expect(f.severity, FindingSeverity.blocking);
      }
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

/// 生成一个含指定行数的合法 Dart 文件内容，包含一个单一公开类。
///
/// 行数构成：`class ... { ... }` 框架 + 大量注释行；总行数等于参数 `lines`。
String _generateDartFileContent({
  required int lines,
  required String publicClassName,
}) {
  final buffer = StringBuffer()
    ..writeln('// 测试用 Dart 文件，仅用于 FileSizeRule 行数门禁回归。')
    ..writeln('class $publicClassName {')
    ..writeln('  void noop() {}');
  // buffer 当前 3 行，目标 lines 行；末尾还要追加 `}`，所以注释占 lines - 4 行。
  final commentLineCount = lines - 4;
  for (var i = 0; i < commentLineCount; i++) {
    buffer.writeln('  // padding line $i');
  }
  buffer.writeln('}');
  return buffer.toString();
}

/// 生成豁免名单内的 tts_engine_service 测试内容，需同时满足 TtsLifecycleRule
/// 的 dispose snippet 要求，避免污染 blocking 计数。
String _generateBigTtsEngineService({required int lines}) {
  final buffer = StringBuffer()
    ..writeln('class TtsEngineService {')
    ..writeln('  void dispose() {')
    ..writeln('    _progressController.close();')
    ..writeln('    _audioPlayer.dispose();')
    ..writeln('    _fallbackEngine.stop();')
    ..writeln('    _wakeLock.disable();')
    ..writeln('  }');
  // 当前 7 行；目标 lines 行；末尾 `}`，padding 占 lines - 8 行。
  final padding = lines - 8;
  for (var i = 0; i < padding; i++) {
    buffer.writeln('  // padding line $i');
  }
  buffer.writeln('}');
  return buffer.toString();
}
