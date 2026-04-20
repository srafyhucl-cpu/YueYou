import 'dart:io';

/// TTS 配置类
class TtsConfig {
  final String serverUrl;
  final Duration requestTimeout;
  final int maxRetries;
  final Duration baseRetryDelay;
  final int maxPrefetchQueue;

  const TtsConfig({
    required this.serverUrl,
    this.requestTimeout = const Duration(seconds: 8),
    this.maxRetries = 2,
    this.baseRetryDelay = const Duration(milliseconds: 800),
    this.maxPrefetchQueue = 6,
  });

  /// 开发环境配置（通过 --dart-define=TTS_SERVER_URL=http://your-server:3000/api/v1/tts/createStream 指定）
  static const TtsConfig development = TtsConfig(
    serverUrl: 'http://localhost:8080/api/v1/tts',
  );

  /// 生产环境配置（通过 --dart-define=TTS_SERVER_URL 覆盖）
  static const TtsConfig production = TtsConfig(
    serverUrl: 'http://localhost:8080/api/v1/tts',
  );

  /// 当前环境配置
  static TtsConfig get current {
    // 从环境变量中读取服务器地址
    final serverUrl = Platform.environment['TTS_SERVER_URL'];
    if (serverUrl != null && serverUrl.isNotEmpty) {
      return TtsConfig(serverUrl: serverUrl);
    }
    // 默认开发环境
    return development;
  }
}
