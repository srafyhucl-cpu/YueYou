import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CyberLogger.resetForTesting();
  });

  // ── recordFlutterError ────────────────────────────────────────────────────

  group('CyberLogger.recordFlutterError', () {
    test('Sentry 未就绪时不崩溃', () {
      expect(
        () => CyberLogger.recordFlutterError(
          FlutterErrorDetails(
            exception: Exception('UI 渲染异常'),
            stack: StackTrace.current,
            library: 'test_library',
          ),
        ),
        returnsNormally,
      );
    });

    test('传入空 stack 时不崩溃', () {
      expect(
        () => CyberLogger.recordFlutterError(
          const FlutterErrorDetails(exception: 'simple string error'),
        ),
        returnsNormally,
      );
    });

    test('传入复杂异常与上下文时不崩溃', () {
      expect(
        () => CyberLogger.recordFlutterError(
          FlutterErrorDetails(
            exception: StateError('非法状态'),
            stack: StackTrace.current,
            library: 'game_provider',
            context: ErrorDescription('2048 棋盘更新时'),
          ),
        ),
        returnsNormally,
      );
    });
  });

  // ── recordPlatformError ───────────────────────────────────────────────────

  group('CyberLogger.recordPlatformError', () {
    test('debug 模式返回 false（保留红屏调试）', () {
      // 测试环境 kReleaseMode = false
      final result = CyberLogger.recordPlatformError(
        Exception('Zone 外异步崩溃'),
        StackTrace.current,
      );
      expect(result, isFalse);
    });

    test('MissingPluginException 在 debug 模式也返回 true', () {
      final result = CyberLogger.recordPlatformError(
        MissingPluginException('插件未注册'),
        StackTrace.current,
      );
      expect(result, isTrue);
    });

    test('Sentry 未就绪时不崩溃', () {
      expect(
        () => CyberLogger.recordPlatformError(
          Exception('平台崩溃'),
          StackTrace.current,
        ),
        returnsNormally,
      );
    });
  });

  // ── captureWarning ────────────────────────────────────────────────────────

  group('CyberLogger.captureWarning', () {
    test('传入完整参数时不崩溃', () {
      expect(
        () => CyberLogger.captureWarning(
          Exception('TTS 请求失败'),
          stack: StackTrace.current,
          tag: 'tts',
          extra: {'step': 'download', 'retry': '2'},
        ),
        returnsNormally,
      );
    });

    test('extra 为 null 时不崩溃', () {
      expect(
        () => CyberLogger.captureWarning(
          Exception('文件解析错误'),
          tag: 'file_import',
        ),
        returnsNormally,
      );
    });

    test('stack 为 null 时不崩溃', () {
      expect(
        () => CyberLogger.captureWarning(Exception('网络超时')),
        returnsNormally,
      );
    });
  });

  // ── captureMessage ────────────────────────────────────────────────────────

  group('CyberLogger.captureMessage', () {
    test('Sentry 未就绪时不崩溃', () {
      expect(
        () => CyberLogger.captureMessage('TTS 初始化完成'),
        returnsNormally,
      );
    });

    test('Sentry 就绪状态注入后路径可达', () {
      CyberLogger.setReadyForTesting(true);
      // Sentry SDK 在测试环境未真正初始化，忽略其内部异常
      try {
        CyberLogger.captureMessage('测试消息');
      } catch (_) {}
    });
  });

  // ── sanitize 脱敏 ─────────────────────────────────────────────────────────

  group('CyberLogger.sanitize', () {
    test('不含查询参数的字符串保持不变', () {
      const raw = 'https://example.com/audio.mp3';
      expect(CyberLogger.sanitize(raw), raw);
    });

    test('含查询参数的 URL 截断参数', () {
      const raw = 'https://example.com/audio.mp3?token=abc123&key=xyz';
      final result = CyberLogger.sanitize(raw);
      expect(result, 'https://example.com/audio.mp3?[REDACTED]');
      expect(result, isNot(contains('abc123')));
    });

    test('普通文本中不含 ? 则不变', () {
      const raw = 'TTS 请求失败，重试次数已达上限';
      expect(CyberLogger.sanitize(raw), raw);
    });

    test('空字符串不崩溃', () {
      expect(CyberLogger.sanitize(''), '');
    });

    test('仅含 ? 的字符串处理正确', () {
      expect(CyberLogger.sanitize('?'), '?[REDACTED]');
    });
  });

  // ── sanitizeStack 堆栈脱敏 ───────────────────────────────────────────────

  group('CyberLogger.sanitizeStack', () {
    test('Windows 绝对路径被替换', () {
      const stack =
          '#0  main (C:\\\\Users\\\\srafy\\\\yueyou\\\\lib\\\\main.dart:20)';
      final result = CyberLogger.sanitizeStack(stack);
      expect(result, isNot(contains('srafy')));
      expect(result, contains('[PATH_REDACTED]'));
    });

    test('Unix 绝对路径被替换', () {
      const stack = '#0  main (/home/user/yueyou/lib/main.dart:20)';
      final result = CyberLogger.sanitizeStack(stack);
      expect(result, isNot(contains('/home/user')));
      expect(result, contains('[PATH_REDACTED]'));
    });

    test('包路径不被替换', () {
      const stack = '#0  main (package:yueyou/main.dart:20)';
      expect(CyberLogger.sanitizeStack(stack), stack);
    });

    test('空堆栈不崩溃', () {
      expect(CyberLogger.sanitizeStack(''), '');
    });
  });

  // ── initSentry DSN 为空时静默跳过 ────────────────────────────────────────

  group('CyberLogger.initSentry', () {
    test('DSN 为空时直接执行 appRunner', () async {
      bool ranApp = false;
      await CyberLogger.initSentry(() async {
        ranApp = true;
      });
      expect(ranApp, isTrue);
    });
  });
}
