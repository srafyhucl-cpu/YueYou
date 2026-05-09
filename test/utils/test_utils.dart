import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/config/tts_config.dart' as config;
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/reader/domain/text_parser.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';

// ── 共享 Fake 实现 ──────────────────────────────────────────────────────────

/// 假音频播放器：所有方法空实现，Stream 返回空流
class FakeAudioPlayer implements TtsAudioPlayer {
  @override
  Future<void> setSource(Source source) async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setPlaybackRate(double rate) async {}
  @override
  Future<void> setAudioContext(AudioContext context) async {}
  @override
  Stream<void> get onPlayerComplete => const Stream<void>.empty();
  @override
  Stream<Duration> get onDurationChanged => const Stream.empty();
  @override
  Stream<Duration> get onPositionChanged => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

/// 假 HTTP 客户端：可自定义响应
class FakeHttpClient implements TtsHttpClient {
  final TtsHttpResponse response;
  int requestCount = 0;

  FakeHttpClient([
    this.response = const TtsHttpResponse(
      statusCode: 200,
      body: '{"status": "success", "url": "https://example.com/audio.mp3"}',
    ),
  ]);

  @override
  Future<TtsHttpResponse> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    requestCount++;
    return response;
  }

  @override
  Future<void> download(Uri url, String savePath) async {}
}

/// 假唤醒锁
class FakeWakeLock implements TtsWakeLock {
  @override
  Future<void> enable() async {}
  @override
  Future<void> disable() async {}
}

/// 假本地 TTS 降级引擎
class FakeFallbackEngine implements TtsFallbackEngine {
  @override
  Future<void> initialize() async {}
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

// ── 环境初始化 ─────────────────────────────────────────────────────────────

/// 初始化测试环境：SharedPreferences mock + StorageService + 全部平台 Channel mock
Future<void> initializeTestEnvironment() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  StorageService.resetForTesting();
  await StorageService.init();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // path_provider
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (methodCall) async {
      if (methodCall.method == 'getTemporaryDirectory') return '.';
      if (methodCall.method == 'getApplicationDocumentsDirectory') return '.';
      return '.';
    },
  );
  // audioplayers
  messenger.setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers.global'),
    (methodCall) async => null,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers'),
    (methodCall) async => null,
  );
  // wakelock
  messenger.setMockMethodCallHandler(
    const MethodChannel('wakelock_plus'),
    (methodCall) async => null,
  );
  // haptic
  messenger.setMockMethodCallHandler(
    const MethodChannel('flutter/haptic'),
    (methodCall) async => null,
  );
  // platform
  messenger.setMockMethodCallHandler(
    const MethodChannel('flutter/platform', JSONMethodCodec()),
    (methodCall) async => null,
  );
  // system_sound
  messenger.setMockMethodCallHandler(
    const MethodChannel('flutter/system_sound'),
    (methodCall) async => null,
  );
}

/// 初始化测试环境并把 path_provider 重定向到独立 [Directory.systemTemp] 子目录。
///
/// 用于需要文件读写隔离的测试（如 [DefaultBookService] 的章节缓存、
/// [FileImportService] 的临时文件）。每个用例独立 temp dir 可避免缓存交叉
/// 污染、跨用例残留文件。
///
/// 用法：
/// ```dart
/// late Directory tempDir;
/// setUp(() async {
///   tempDir = await initializeTestEnvironmentWithIsolatedTempDir('yueyou_book_');
/// });
/// tearDown(() async {
///   try {
///     if (await tempDir.exists()) await tempDir.delete(recursive: true);
///   } catch (_) {}
/// });
/// ```
Future<Directory> initializeTestEnvironmentWithIsolatedTempDir(
  String prefix,
) async {
  await initializeTestEnvironment();
  StorageService.resetForTesting();
  await StorageService.init();

  final tempDir = await Directory.systemTemp.createTemp(prefix);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => tempDir.path,
  );
  return tempDir;
}

// ── 共享工厂方法 ──────────────────────────────────────────────────────────

/// 创建已初始化的 SettingsProvider（所有 late 字段赋值）
SettingsProvider makeSettings() {
  final s = SettingsProvider()..loadFromStorage();
  s.voice = 'zh-CN-XiaoxiaoNeural';
  s.ttsRate = 1.0;
  s.idleTimeout = 0;
  s.sound = true;
  s.storyTts = false;
  s.ambientVol = 0.5;
  s.ambientEnabled = false;
  return s;
}

/// 创建 TtsEngineService（注入全部 Fake，delayFn 默认永不完成以阻止兼容循环空转）
TtsEngineService makeTtsEngine(
  SettingsProvider settings, {
  TtsHttpClient? httpClient,
  Future<void> Function(Duration)? delayFn,
}) {
  return TtsEngineService(
    settings,
    config: const config.TtsConfig(serverUrl: 'http://test.com/tts'),
    audioPlayer: FakeAudioPlayer(),
    wakeLock: FakeWakeLock(),
    httpClient: httpClient ?? FakeHttpClient(),
    fallbackEngine: FakeFallbackEngine(),
    delayFn: delayFn ?? (_) => Completer<void>().future,
  );
}

/// 创建 ReaderProvider + TtsEngineService 组合（纯逻辑测试用）
Future<(ReaderProvider, TtsEngineService)> makeReaderStack({
  TtsHttpClient? httpClient,
  Future<ParseResult> Function(String)? parseBook,
}) async {
  await initializeTestEnvironment();
  final settings = makeSettings();
  final engine = makeTtsEngine(settings, httpClient: httpClient);
  final reader = ReaderProvider(engine, parseBook: parseBook);
  return (reader, engine);
}
