/// TTS 配置类
class TtsConfig {
  final String serverUrl;
  final Duration requestTimeout;
  final int maxRetries;
  final Duration baseRetryDelay;
  final int maxPrefetchQueue;

  const TtsConfig({
    required this.serverUrl,
    this.requestTimeout = const Duration(seconds: 10),
    this.maxRetries = 3,
    this.baseRetryDelay = const Duration(seconds: 1),
    this.maxPrefetchQueue = 3,
  });

  /// 开发环境配置
  static const TtsConfig development = TtsConfig(
    serverUrl: 'http://8.218.177.149:3000/api/v1/tts/createStream',
  );

  /// 生产环境配置
  static const TtsConfig production = TtsConfig(
    serverUrl: 'https://api.yueyou.com/v1/tts/createStream',
  );

  /// 当前环境配置
  static TtsConfig get current {
    // 可以根据编译常量或环境变量切换
    return development; // 默认开发环境
  }
}
