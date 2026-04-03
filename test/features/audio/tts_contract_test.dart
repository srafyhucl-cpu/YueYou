import 'dart:async';
import 'dart:convert';
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
  Future<TtsHttpResponse> post(Uri url,
      {Map<String, String>? headers, Object? body}) async {
    return TtsHttpResponse(statusCode: statusCode, body: jsonEncode(response));
  }

  @override
  Future<void> download(Uri url, String savePath) async {
    wasDownloadCalled = true;
    downloadedUrl = url.toString();
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
  Stream<void> get onPlayerComplete => Stream<void>.empty();

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
        delayFn: (d) => Future<void>.delayed(Duration.zero),
      );

      // 模拟初始化完成
      await Future.delayed(Duration.zero);
    });

    test('遵循“分离下载”原则 - 先获取URL再单独下载', () async {
      // 模拟请求下一句文本
      ttsService.onNeedPrefetch = (session) async {
        return TtsAudioRequest(
          text: '测试文本内容足够长以通过短句过滤',
          lineIndex: 0,
          title: '测试标题',
        );
      };

      // 启动预加载循环
      ttsService.setEnabled(true);
      await Future.delayed(Duration.zero);

      // 验证 POST 请求获取 JSON 响应
      expect(mockHttpClient.wasDownloadCalled, isFalse,
          reason: '在获取JSON响应前不应调用下载');

      // 等待下载逻辑执行
      await Future.delayed(Duration(milliseconds: 100));

      // 验证从返回的URL下载音频
      expect(mockHttpClient.wasDownloadCalled, isTrue, reason: '应从返回的URL下载音频');
      expect(mockHttpClient.downloadedUrl, 'https://example.com/audio.mp3',
          reason: '下载URL应与JSON响应中的URL一致');
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
        delayFn: (d) => Future<void>.delayed(Duration.zero),
      );

      ttsService.onNeedPrefetch = (session) async {
        return TtsAudioRequest(
          text: '测试文本内容足够长以通过短句过滤',
          lineIndex: 0,
          title: '测试标题',
        );
      };

      ttsService.setEnabled(true);
      await Future.delayed(Duration(milliseconds: 100));

      // 验证不下载无效URL
      expect(mockHttpClient.wasDownloadCalled, isFalse, reason: '不应下载无效URL');
      expect(ttsService.lastError, isNotNull, reason: '应设置错误信息');
      expect(ttsService.lastError, contains('TTS 服务错误'),
          reason: '错误信息应包含 TTS 服务错误');
    });
  });
}
