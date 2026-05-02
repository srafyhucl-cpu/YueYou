/// TTS 配置类
///
/// 所有服务器地址通过 `--dart-define` 编译时注入，严禁硬编码 IP 或域名。
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

  /// 编译时注入的 TTS 服务器地址（--dart-define=TTS_SERVER_URL=https://...）
  static const String _ttsServerUrl = String.fromEnvironment(
    'TTS_SERVER_URL',
    defaultValue: 'https://hclstudio.cn/api/v1/tts',
  );

  /// 编译时注入的书籍 API 基础地址（--dart-define=BOOK_API_BASE=https://...）
  static const String bookApiBase = String.fromEnvironment(
    'BOOK_API_BASE',
    defaultValue: 'https://hclstudio.cn/api/v1',
  );

  /// 当前环境配置（编译时确定，零运行时开销）
  static const TtsConfig current = TtsConfig(
    serverUrl: _ttsServerUrl,
  );
}
