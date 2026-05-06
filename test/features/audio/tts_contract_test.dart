import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';
import 'package:yueyou/core/config/tts_config.dart';
import 'package:audioplayers/audioplayers.dart';

class MockHttpClient implements TtsHttpClient {
  final Map<String, dynamic> response;
  final int statusCode;
  bool wasDownloadCalled = false;
  String? downloadedUrl;

  MockHttpClient({required this.response, this.statusCode = 200});

  @override
  Future<TtsHttpResponse> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    return TtsHttpResponse(statusCode: statusCode, body: jsonEncode(response));
  }

  @override
  Future<void> download(Uri url, String savePath) async {
    wasDownloadCalled = true;
    downloadedUrl = url.toString();
    final file = File(savePath);
    if (!await file.exists()) {
      await file.create(recursive: true);
      await file.writeAsBytes(Uint8List(100));
    }
  }
}

class MockAudioPlayer implements TtsAudioPlayer {
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

class MockWakeLock implements TtsWakeLock {
  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}
}

void _mockPathProviderChannel() {
  const MethodChannel channel =
      MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    return '.';
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TtsEngineService - 契约测试', () {
    late TtsEngineService ttsService;
    late MockHttpClient mockHttpClient;
    late SettingsProvider settings;

    setUp(() async {
      _mockPathProviderChannel();

      settings = SettingsProvider();
      settings.voice = 'zh-CN-XiaoxiaoNeural';
      settings.ttsRate = 1.0;
      settings.idleTimeout = 0;
      settings.sound = true;
      settings.storyTts = true;
      settings.ambientVol = 0.5;
      settings.ambientEnabled = false;

      mockHttpClient = MockHttpClient(
        response: {'status': 'success', 'url': 'https://example.com/audio.mp3'},
      );

      ttsService = TtsEngineService(
        settings,
        config: const TtsConfig(serverUrl: 'http://test.com/tts'),
        audioPlayer: MockAudioPlayer(),
        wakeLock: MockWakeLock(),
        httpClient: mockHttpClient,
        delayFn: (d) => Future<void>.delayed(const Duration(milliseconds: 1)),
      );

      // 模拟初始化完成
      await Future.delayed(const Duration(milliseconds: 1));
    });

    // 用例结束后恢复 path_provider mock 到系统临时目录，
    // 防止污染串行运行时的后续测试文件（如 tts_engine_service_test.dart）
    tearDown(() {
      const MethodChannel channel =
          MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        return Directory.systemTemp.path;
      });
    });

    test('遵循"分离下载"原则 - 先获取URL再单独下载', () async {
      final request = TtsAudioRequest(
        text: '测试文本内容足够长以通过短句过滤',
        lineIndex: 0,
        title: '测试标题',
      );

      final result = await ttsService.downloadAudio(request);

      expect(result, isNotNull, reason: '应成功下载音频文件');
      expect(
        mockHttpClient.wasDownloadCalled,
        isTrue,
        reason: '应从返回的URL下载音频',
      );
      expect(
        mockHttpClient.downloadedUrl,
        'https://example.com/audio.mp3',
        reason: '下载URL应与JSON响应中的URL一致',
      );
    });

    test('处理错误响应 - 不下载无效URL', () async {
      // 模拟一个错误的响应
      mockHttpClient = MockHttpClient(
        response: {'status': 'error', 'message': '服务器错误'},
        statusCode: 500,
      );

      ttsService = TtsEngineService(
        settings,
        config: const TtsConfig(serverUrl: 'http://test.com/tts'),
        audioPlayer: MockAudioPlayer(),
        wakeLock: MockWakeLock(),
        httpClient: mockHttpClient,
        delayFn: (d) => Future<void>.delayed(const Duration(milliseconds: 1)),
      );

      await Future.delayed(const Duration(milliseconds: 1));

      final request = TtsAudioRequest(
        text: '测试文本内容足够长以通过短句过滤',
        lineIndex: 0,
        title: '测试标题',
      );

      final result = await ttsService.downloadAudio(request);

      expect(result, isNull, reason: '错误响应不应返回文件路径');
      expect(
        mockHttpClient.wasDownloadCalled,
        isFalse,
        reason: '不应下载无效URL',
      );
      expect(ttsService.lastError, isNotNull, reason: '应设置错误信息');
    });
  });
}
