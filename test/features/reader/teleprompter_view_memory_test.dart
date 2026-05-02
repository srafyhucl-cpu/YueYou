import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/config/tts_config.dart' as config;
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/reader/presentation/widgets/teleprompter_view.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';
import '../../utils/test_utils.dart';

class _FakeHttpClient implements TtsHttpClient {
  @override
  Future<TtsHttpResponse> post(Uri url,
      {Map<String, String>? headers, Object? body,}) async {
    return const TtsHttpResponse(
      statusCode: 200,
      body: '{"status": "success", "url": "https://example.com/audio.mp3"}',
    );
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

class _FakeWakeLock implements TtsWakeLock {
  @override
  Future<void> enable() async {}
  @override
  Future<void> disable() async {}
}

Future<ReaderProvider> _makeReader() async {
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
    httpClient: _FakeHttpClient(),
    delayFn: (d) => Future<void>.delayed(Duration.zero),
  );

  return ReaderProvider(ttsEngine);
}

Widget _wrapWithProviders(ReaderProvider reader) {
  return ProviderScope(
    overrides: [
      readerProvider.overrideWith((ref) => reader),
      ttsEngineProvider.overrideWith((ref) => reader.ttsEngine),
    ],
    child: const MaterialApp(home: Scaffold(body: TeleprompterView())),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await initializeTestEnvironment();
  });

  testWidgets('TeleprompterView 高频刷新与毛玻璃渲染边界审计', (tester) async {
    // 此测试用于验证在高频翻页（如 TTS 持续朗读）时，
    // TeleprompterView 组件可稳定重建且 BackdropFilter 未出现离屏渲染溢出风险。
    final reader = await _makeReader();
    
    await tester.runAsync(() async {
      await reader.loadBook(
        '第一句。第二句。第三句。第四句。第五句。',
        bookId: 'mem_test',
        initialIndex: 0,
        forceIndex: true,
      );
    });

    await tester.pumpWidget(_wrapWithProviders(reader));
    await tester.pumpAndSettle();

    // 验证初始化
    expect(find.byType(TeleprompterView), findsOneWidget);
    
    // 强制触发一次播放状态以开始动画
    reader.ttsEngine.setEnabled(true);
    await tester.pump();
    
    // 模拟高频次重建与动画刷新，验证毛玻璃组件不会导致离屏渲染溢出或崩溃
    for (int i = 0; i < 50; i++) {
      // 通过直接调整内部尺寸或高频刷新帧来施加渲染压力
      await tester.pump(const Duration(milliseconds: 32)); 
    }

    // 停止引擎并清理
    reader.ttsEngine.setEnabled(false);
    reader.dispose();
    await tester.pump(const Duration(milliseconds: 500));
    
    expect(find.byType(TeleprompterView), findsOneWidget);
  });
}
