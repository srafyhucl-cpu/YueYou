import 'package:flutter/foundation.dart';

/// 赛博朋克风格全局错误捕获与格式化日志模块
///
/// V1.0：仅 debugPrint 输出到控制台，保留标准格式供后续接入 Sentry/Crashlytics
/// TODO: V1.1 接入 Sentry/Crashlytics，将 _emit 替换为 SDK 上报调用
class CyberLogger {
  CyberLogger._();

  /// 捕获 FlutterError.onError（UI 层红屏、渲染异常）
  static void recordFlutterError(FlutterErrorDetails details) {
    final StringBuffer buf = StringBuffer()
      ..writeln('╔══ [CYBER-ERROR] Flutter UI Exception ══════════════════════')
      ..writeln('║  Time   : ${DateTime.now().toIso8601String()}')
      ..writeln('║  Library: ${details.library ?? 'unknown'}')
      ..writeln('║  Context: ${details.context ?? 'unknown'}')
      ..writeln('║  Summary: ${details.exceptionAsString()}')
      ..writeln('╟── Stack Trace ──────────────────────────────────────────────')
      ..writeln(details.stack ?? '(no stack trace)')
      ..writeln('╚════════════════════════════════════════════════════════════');
    _emit(buf.toString());

    // TODO: V1.1 接入 Sentry/Crashlytics
    // Sentry.captureException(details.exception, stackTrace: details.stack);
  }

  /// 捕获 PlatformDispatcher.instance.onError（Zone 外异步崩溃）
  /// 返回 false 以保持默认的崩溃行为（便于调试），可改为 true 吞掉崩溃
  static bool recordPlatformError(Object error, StackTrace stack) {
    final StringBuffer buf = StringBuffer()
      ..writeln('╔══ [CYBER-ERROR] Uncaught Async Exception ═══════════════════')
      ..writeln('║  Time  : ${DateTime.now().toIso8601String()}')
      ..writeln('║  Error : $error')
      ..writeln('║  Type  : ${error.runtimeType}')
      ..writeln('╟── Stack Trace ──────────────────────────────────────────────')
      ..writeln(stack)
      ..writeln('╚════════════════════════════════════════════════════════════');
    _emit(buf.toString());

    // TODO: V1.1 接入 Sentry/Crashlytics
    // Sentry.captureException(error, stackTrace: stack);

    return false;
  }

  static void _emit(String message) {
    debugPrint(message);
  }
}
