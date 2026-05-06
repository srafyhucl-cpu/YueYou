import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// 赛博朋克风格全局错误捕获、日志格式化与 Sentry 分级上报模块
///
/// ## 分级上报策略
/// - **严重 (fatal)**：未捕获的平台崩溃（`PlatformDispatcher.onError`），
///   不可恢复，立即上报，附带设备信息与完整堆栈。
/// - **普通 (error)**：Flutter UI 层异常（`FlutterError.onError`），
///   可能导致页面红屏，上报并继续运行。
/// - **警告 (warning)**：业务层主动上报的已知异常，不影响主流程。
///
/// ## 日志脱敏规则
/// - 自动过滤 URL 中的查询参数（可能含临时 Token）
/// - 自动过滤堆栈中的本地文件系统绝对路径
/// - 严禁上报用户阅读内容、进度数据（已通过架构隔离保证）
///
/// ## DSN 注入方式
/// 通过 `--dart-define=SENTRY_DSN=https://...` 编译时注入，
/// 严禁硬编码到源码中。
class CyberLogger {
  CyberLogger._();

  /// 编译时注入的 Sentry DSN（见 `--dart-define=SENTRY_DSN=...`）
  static const String _sentryDsn =
      String.fromEnvironment('SENTRY_DSN', defaultValue: '');

  /// Sentry 是否已完成初始化（DSN 有效且 init 成功）
  static bool _sentryReady = false;

  /// 初始化 Sentry（在 [SentryFlutter.init] 回调中调用 [runApp]）
  ///
  /// 用法（替换原 main.dart 中的 runApp）：
  /// ```dart
  /// await CyberLogger.initSentry(() => runApp(const YueYouApp()));
  /// ```
  ///
  /// DSN 为空时（开发环境未配置）静默跳过 Sentry 初始化，不影响运行。
  static Future<void> initSentry(AppRunner appRunner) async {
    if (_sentryDsn.isEmpty) {
      debugPrint('[CyberLogger] SENTRY_DSN 未配置，跳过 Sentry 初始化（本地开发模式）');
      await appRunner();
      return;
    }

    await SentryFlutter.init(
      (options) {
        options.dsn = _sentryDsn;
        // release 模式才采样上报，debug 模式采样率为 0
        options.tracesSampleRate = kReleaseMode ? 0.2 : 0.0;
        // 日志级别：debug 模式详细，release 模式仅 warning+
        options.diagnosticLevel =
            kReleaseMode ? SentryLevel.warning : SentryLevel.debug;
        // 隐私合规：严禁截图和 PII
        options.attachScreenshot = false;
        options.sendDefaultPii = false;
        // 环境与版本标记
        options.environment = kReleaseMode ? 'production' : 'development';
        options.release =
            'yueyou@${const String.fromEnvironment('APP_VERSION', defaultValue: '1.1.0')}';
      },
      appRunner: appRunner,
    );
    _sentryReady = true;
    debugPrint('[CyberLogger] Sentry 初始化完成');
  }

  // ── 公开上报接口 ──────────────────────────────────────────────────────────

  /// 捕获 FlutterError.onError（UI 层红屏、渲染异常）— 普通级别
  static void recordFlutterError(FlutterErrorDetails details) {
    _printFormatted(
      tag: 'Flutter UI Exception',
      error: details.exceptionAsString(),
      library: details.library,
      context: details.context?.toString(),
      stack: details.stack,
    );

    if (!_sentryReady) return;
    Sentry.captureException(
      details.exception,
      stackTrace: details.stack,
      withScope: (scope) {
        scope.level = SentryLevel.error;
        scope.setTag('source', 'flutter_error');
        scope.setTag('library', sanitize(details.library ?? 'unknown'));
      },
    );
  }

  /// 捕获 PlatformDispatcher.instance.onError（Zone 外异步崩溃）— 严重级别
  ///
  /// 返回 false 以保持默认崩溃行为（debug 模式保留红屏）
  static bool recordPlatformError(Object error, StackTrace stack) {
    _printFormatted(
      tag: 'Uncaught Async Exception',
      error: error.toString(),
      stack: stack,
      isFatal: true,
    );

    if (_sentryReady) {
      Sentry.captureException(
        error,
        stackTrace: stack,
        withScope: (scope) {
          scope.level = SentryLevel.fatal;
          scope.setTag('source', 'platform_error');
        },
      );
    }

    // release 模式返回 true 吞掉崩溃，防止 Android Kill 进程
    if (kReleaseMode) return true;
    // MissingPluginException 在 debug 模式也吞掉，避免开发干扰
    if (error is MissingPluginException) return true;
    return false;
  }

  /// 主动上报业务层已知异常（警告级别，不影响主流程）
  ///
  /// 适用于：TTS 请求失败、文件解析错误等可恢复的业务异常。
  ///
  /// - [error]：异常对象
  /// - [stack]：堆栈（可选）
  /// - [tag]：上报分类标签（如 'tts'、'file_import'）
  /// - [extra]：附加的脱敏上下文信息（禁止传入用户内容）
  static void captureWarning(
    Object error, {
    StackTrace? stack,
    String tag = 'business',
    Map<String, String>? extra,
  }) {
    _printFormatted(
      tag: 'Warning [$tag]',
      error: error.toString(),
      stack: stack,
    );

    if (!_sentryReady) return;
    Sentry.captureException(
      error,
      stackTrace: stack,
      withScope: (scope) {
        scope.level = SentryLevel.warning;
        scope.setTag('source', tag);
        if (extra != null) {
          scope.setContexts(
            'business_context',
            extra.map((k, v) => MapEntry(k, sanitize(v))),
          );
        }
      },
    );
  }

  /// 上报一条纯文本消息（不含异常，用于关键业务节点埋点）
  ///
  /// - [message]：消息内容（请勿包含用户数据）
  /// - [level]：日志级别（默认 info）
  /// - [tag]：模块标签（如 'tts'、'reader'、'library'），用于 Sentry 按模块过滤
  static void captureMessage(
    String message, {
    SentryLevel level = SentryLevel.info,
    String tag = 'business',
  }) {
    debugPrint('[CyberLogger][${level.name.toUpperCase()}][$tag] $message');
    if (!_sentryReady) return;
    Sentry.captureMessage(
      sanitize(message),
      level: level,
      withScope: (scope) => scope.setTag('source', tag),
    );
  }

  // ── 内部工具 ──────────────────────────────────────────────────────────────

  /// 格式化输出到控制台（统一日志格式）
  static void _printFormatted({
    required String tag,
    required String error,
    String? library,
    String? context,
    StackTrace? stack,
    bool isFatal = false,
  }) {
    final border = isFatal ? '[CYBER-FATAL]' : '[CYBER-ERROR]';
    final buf = StringBuffer()
      ..writeln('===== $border $tag =====')
      ..writeln('  Time    : ${DateTime.now().toIso8601String()}')
      ..writeln('  Error   : ${sanitize(error)}');
    if (library != null) buf.writeln('  Library : ${sanitize(library)}');
    if (context != null) buf.writeln('  Context : ${sanitize(context)}');
    if (stack != null) {
      buf
        ..writeln('--- Stack Trace ---')
        ..writeln(sanitizeStack(stack.toString()));
    }
    buf.writeln('==================');
    debugPrint(buf.toString());
  }

  /// 脱敏处理：过滤 URL 查询参数（可能含临时 Token/Key）
  ///
  /// 对外暴露以便测试验证脱敏逻辑。
  @visibleForTesting
  static String sanitize(String raw) {
    // 截断 URL 中 ? 后的查询参数
    final idx = raw.indexOf('?');
    if (idx >= 0) return '${raw.substring(0, idx)}?[REDACTED]';
    return raw;
  }

  /// 堆栈脱敏：过滤本地绝对路径（Windows / Linux / Mac 均覆盖）
  @visibleForTesting
  static String sanitizeStack(String stack) {
    return stack
        // Windows 绝对路径 C:\Users\...
        .replaceAll(
          RegExp(r'[A-Za-z]:[/\\][^\s)]+'),
          '[PATH_REDACTED]',
        )
        // Unix 绝对路径 /home/... /Users/...
        .replaceAll(
          RegExp(r'/(?:home|Users|root)/[^\s)]+'),
          '[PATH_REDACTED]',
        );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 测试专用：注入 ready 状态（不得在生产代码中调用）
  // ─────────────────────────────────────────────────────────────────────────

  /// 测试专用：强制设置 Sentry 就绪状态
  @visibleForTesting
  static void setReadyForTesting(bool ready) => _sentryReady = ready;

  /// 测试专用：重置 Sentry 就绪状态
  @visibleForTesting
  static void resetForTesting() => _sentryReady = false;
}
