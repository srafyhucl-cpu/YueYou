import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/config/tts_config.dart' as config;
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/reader/presentation/widgets/teleprompter_view.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';
import '../../utils/test_utils.dart';

class _FakeHttpClient implements TtsHttpClient {
  final TtsHttpResponse response;

  _FakeHttpClient(this.response);

  @override
  Future<TtsHttpResponse> post(Uri url,
      {Map<String, String>? headers, Object? body}) async {
    return response;
  }

  @override
  Future<void> download(Uri url, String savePath) async {}
}

class _FakeAudioPlayer implements TtsAudioPlayer {
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
  Stream<void> get onPlayerComplete => const Stream<void>.empty();

  @override
  Future<void> dispose() async {}
}

class _FakeWakeLock implements TtsWakeLock {
  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}
}

Future<ReaderProvider> _makeReader({TtsHttpClient? httpClient}) async {
  SharedPreferences.setMockInitialValues({});
  StorageService.resetForTesting();
  await StorageService.init();
  const MethodChannel global = MethodChannel('xyz.luan/audioplayers.global');
  const MethodChannel player = MethodChannel('xyz.luan/audioplayers');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(global, (MethodCall call) async => null);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(player, (MethodCall call) async => null);

  final settings = SettingsProvider();
  settings.loadFromStorage();
  settings.voice = 'zh-CN-XiaoxiaoNeural';
  settings.ttsRate = 1.0;
  settings.idleTimeout = 0;
  settings.sound = true;
  settings.storyTts = false;
  settings.ambientVol = 0.5;
  settings.ambientEnabled = false;

  final ttsEngine = TtsEngineService(
    settings,
    config: const config.TtsConfig(serverUrl: 'http://test.com/tts'),
    audioPlayer: _FakeAudioPlayer(),
    wakeLock: _FakeWakeLock(),
    httpClient: httpClient ??
        _FakeHttpClient(const TtsHttpResponse(
            statusCode: 200,
            body:
                '{"status": "success", "url": "https://example.com/audio.mp3"}')),
    delayFn: (d) => Future<void>.delayed(Duration.zero),
  );

  return ReaderProvider(ttsEngine);
}

Widget _wrapWithProviders(ReaderProvider reader) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: reader),
    ],
    child: const MaterialApp(home: Scaffold(body: TeleprompterView())),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await initializeTestEnvironment();
  });

  testWidgets('空数据时显示等待占位文本', (tester) async {
    final reader = await _makeReader();
    final service = reader.ttsEngine;
    addTearDown(() {
      reader.dispose();
      service.dispose();
    });
    await tester.pumpWidget(_wrapWithProviders(reader));

    expect(find.text('等待数据流接入 [ _ ]'), findsOneWidget);
  });

  testWidgets('加载文本后渲染 RichText（isPlaying=false）', (tester) async {
    final reader = await _makeReader();
    final service = reader.ttsEngine;
    addTearDown(() {
      reader.dispose();
      service.dispose();
    });
    await tester.runAsync(() async {
      await reader.loadBook(
        '你好世界。',
        bookId: 't1',
        initialIndex: 0,
        forceIndex: true,
      );
    });

    await tester.pumpWidget(_wrapWithProviders(reader));
    await tester.pump();

    expect(find.byType(RichText), findsOneWidget);
    expect(find.textContaining('你好世界', findRichText: true), findsWidgets);
    // isPlaying=false 时不显示中心指示线
    expect(find.byType(Positioned), findsNWidgets(2)); // 仅左右渐隐遮罩的 Positioned 存在
  });

  testWidgets('TTS 错误提示会自动淡出并清理', (tester) async {
    final reader = await _makeReader(
      httpClient: _FakeHttpClient(
        const TtsHttpResponse(statusCode: 404, body: 'not found'),
      ),
    );
    final service = reader.ttsEngine;
    addTearDown(() {
      reader.dispose();
      service.dispose();
    });

    await tester.runAsync(() async {
      await reader.loadBook(
        '你好世界。',
        bookId: 'teleprompter_error_1',
        initialIndex: 0,
        forceIndex: true,
      );
    });

    await tester.pumpWidget(_wrapWithProviders(reader));
    await service.testConnection();
    await tester.pump();

    expect(
        find.byKey(const ValueKey('teleprompter_error_tip')), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const ValueKey('teleprompter_error_tip')), findsNothing);
    expect(reader.ttsErrorMessage, isNotNull);
  });

  testWidgets('点击错误提示后立即清理错误状态', (tester) async {
    final reader = await _makeReader(
      httpClient: _FakeHttpClient(
        const TtsHttpResponse(statusCode: 404, body: 'not found'),
      ),
    );
    final service = reader.ttsEngine;
    addTearDown(() {
      reader.dispose();
      service.dispose();
    });

    await tester.runAsync(() async {
      await reader.loadBook(
        '你好世界。',
        bookId: 'teleprompter_error_2',
        initialIndex: 0,
        forceIndex: true,
      );
    });

    await tester.pumpWidget(_wrapWithProviders(reader));
    await service.testConnection();
    await tester.pump();

    final tipFinder = find.byKey(const ValueKey('teleprompter_error_tip'));
    expect(tipFinder, findsOneWidget);

    await tester.tap(tipFinder);
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const ValueKey('teleprompter_error_tip')), findsNothing);
    expect(reader.ttsErrorMessage, isNull);
    expect(service.lastError, isNull);
  });
}
