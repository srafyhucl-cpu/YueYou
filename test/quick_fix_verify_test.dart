import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/features/audio/providers/tts_audio_notifier.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';
import 'utils/test_utils.dart'; // 修正为相对路径导入
import 'dart:async';

// 极简 Mock 类，防止构造时调用原生插件
class MockAudioPlayer implements TtsAudioPlayer {
  @override
  Future<void> setAudioContext(dynamic context) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setPlaybackRate(double rate) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> dispose() async {}
  @override
  Stream<void> get onPlayerComplete => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockWakeLock implements TtsWakeLock {
  @override
  Future<void> enable() async {}
  @override
  Future<void> disable() async {}
}

class MockFallbackEngine implements TtsFallbackEngine {
  @override
  Future<void> initialize() async {}
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}
}

class FakeTtsEngineService extends TtsEngineService {
  int stopAudioCalls = 0;
  bool syncCalled = false;

  FakeTtsEngineService(SettingsProvider settings) : super(
    settings, 
    externalSettingsListener: false,
    audioPlayer: MockAudioPlayer(),
    wakeLock: MockWakeLock(),
    fallbackEngine: MockFallbackEngine(),
  );

  @override
  Future<void> stopAudio() async { stopAudioCalls++; }
  @override
  Future<void> pauseAudio() async {}
  @override
  void syncSettingsFromProvider(SettingsProvider settings) { syncCalled = true; }
  @override
  void syncShadow({dynamic state, int? session, String? error, dynamic item, String? fallbackMessage}) {}
  @override
  void dispose() {} 
}

class FakeTtsSentenceSource implements TtsSentenceSource {
  bool resetCalled = false;
  @override
  void resetFetchIndex() { resetCalled = true; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('快速验证：切换发声人后的 Session 隔离与降级重置', () async {
    // 1. 使用项目标准初始化工具
    await initializeTestEnvironment();

    final settings = SettingsProvider()..loadFromStorage();
    final fakeEngine = FakeTtsEngineService(settings);
    final fakeSource = FakeTtsSentenceSource();
    
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => settings),
        ttsEngineProvider.overrideWith((ref) => fakeEngine),
      ],
    );

    final notifier = container.read(ttsAudioProvider.notifier);
    notifier.registerSentenceSource(fakeSource);
    
    final initialSession = notifier.currentSession;
    
    // --- 模拟切换动作 ---
    await notifier.refreshSession();
    
    print('\n-----------------------------------------');
    // 验证 1: Session 必须递增
    print('验证 Session 递增: ${notifier.currentSession} > $initialSession');
    expect(notifier.currentSession, initialSession + 1);
    
    // 验证 2: 引擎停止命令必须立即下达（解决旧声音还在播的问题）
    print('验证引擎停止调用次数: ${fakeEngine.stopAudioCalls}');
    expect(fakeEngine.stopAudioCalls, 1);
    
    // 验证 3: 游标重置（解决切换后从头开始读的问题）
    print('验证游标重置调用: ${fakeSource.resetCalled}');
    expect(fakeSource.resetCalled, isTrue);
    
    // 验证 4: 降级标志重置（解决异常降级问题）
    print('验证降级状态已重置: ${!notifier.isDegraded}');
    expect(notifier.isDegraded, isFalse);
    print('-----------------------------------------');

    print('\n✅ 验证通过：切换发声人的即时响应与状态隔离逻辑正常。');
  });
}
