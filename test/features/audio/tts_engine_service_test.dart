import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';

// 简单的手动 Mock 实现
class _FakeAudioPlayer implements TtsAudioPlayer {
  int setSourceCalls = 0;
  int resumeCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int setVolumeCalls = 0;
  int setPlaybackRateCalls = 0;
  int disposeCalls = 0;
  double? lastVolume;
  double? lastPlaybackRate;
  final _controller = StreamController<void>.broadcast();

  @override
  Future<void> setSource(source) async => setSourceCalls++;
  @override
  Future<void> resume() async => resumeCalls++;
  @override
  Future<void> pause() async => pauseCalls++;
  @override
  Future<void> stop() async => stopCalls++;
  @override
  Future<void> setVolume(double volume) async {
    setVolumeCalls++;
    lastVolume = volume;
  }

  @override
  Future<void> setPlaybackRate(double rate) async {
    setPlaybackRateCalls++;
    lastPlaybackRate = rate;
  }

  @override
  Future<void> dispose() async => disposeCalls++;
  @override
  Stream<void> get onPlayerComplete => _controller.stream;
  void completePlayback() => _controller.add(null);
}

class _FakeWakeLock implements TtsWakeLock {
  int enableCalls = 0;
  int disableCalls = 0;
  @override
  Future<void> enable() async => enableCalls++;
  @override
  Future<void> disable() async => disableCalls++;
}

class _Harness {
  final SettingsProvider settings;
  final TtsEngineService service;
  _Harness({required this.settings, required this.service});
}

class _MockHarness {
  final SettingsProvider settings;
  final TtsEngineService service;
  final _FakeAudioPlayer fakeAudioPlayer;
  final _FakeWakeLock fakeWakeLock;
  _MockHarness(
      {required this.settings,
      required this.service,
      required this.fakeAudioPlayer,
      required this.fakeWakeLock});
}

void _mockAudioplayersChannels() {
  const MethodChannel global = MethodChannel('xyz.luan/audioplayers.global');
  const MethodChannel player = MethodChannel('xyz.luan/audioplayers');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(global, (MethodCall call) async {
    return null;
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(player, (MethodCall call) async {
    return null;
  });
}

void _mockWakelockPlusChannel() {
  const MethodChannel channel = MethodChannel('wakelock_plus');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    return null;
  });
}

Future<_Harness> _makeService(
    {bool storyTts = false,
    double ttsRate = 1.0,
    double ambientVol = 0.5,
    String voice = 'zh-CN-XiaoxiaoNeural'}) async {
  SharedPreferences.setMockInitialValues({
    'setting_story_tts': storyTts,
    'setting_tts_rate': ttsRate,
    'setting_ambient_vol': ambientVol,
    'setting_voice': voice
  });
  StorageService.resetForTesting();
  await StorageService.init();
  _mockAudioplayersChannels();
  _mockWakelockPlusChannel();
  final settings = SettingsProvider()..loadFromStorage();
  final service = TtsEngineService(settings);
  await pumpEventQueue(times: 20);
  return _Harness(settings: settings, service: service);
}

Future<_MockHarness> _makeMockService(
    {bool storyTts = false,
    double ttsRate = 1.0,
    double ambientVol = 0.5,
    String voice = 'zh-CN-XiaoxiaoNeural'}) async {
  SharedPreferences.setMockInitialValues({
    'setting_story_tts': storyTts,
    'setting_tts_rate': ttsRate,
    'setting_ambient_vol': ambientVol,
    'setting_voice': voice
  });
  StorageService.resetForTesting();
  await StorageService.init();
  final settings = SettingsProvider()..loadFromStorage();
  final fakeAudioPlayer = _FakeAudioPlayer();
  final fakeWakeLock = _FakeWakeLock();
  final service = TtsEngineService(settings,
      audioPlayer: fakeAudioPlayer, wakeLock: fakeWakeLock);
  await pumpEventQueue(times: 20);
  return _MockHarness(
      settings: settings,
      service: service,
      fakeAudioPlayer: fakeAudioPlayer,
      fakeWakeLock: fakeWakeLock);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TtsEngineService', () {
    test('getVoices 返回固定列表', () async {
      final h = await _makeService();
      final voices = await h.service.getVoices();
      expect(voices.length, 4);
      h.service.dispose();
    });

    test('初始化后 isEnabled 与 SettingsProvider.storyTts 对齐', () async {
      final h = await _makeService(storyTts: true);
      expect(h.service.isEnabled, isTrue);
      h.service.dispose();
    });

    test('cycleSpeed 会更新 playbackRate 并写回设置', () async {
      final h = await _makeService(ttsRate: 1.0);
      final before = h.service.playbackRate;
      h.service.cycleSpeed();
      expect(h.service.playbackRate, isNot(equals(before)));
      await Future<void>.delayed(Duration.zero);
      expect(
          StorageService.getSettingTtsRate(), equals(h.service.playbackRate));
      h.service.dispose();
    });

    test('refreshSession 会递增 session 并清空 currentItem', () async {
      final h = await _makeService();
      final before = h.service.currentSession;
      h.service.refreshSession();
      expect(h.service.currentSession, before + 1);
      expect(h.service.currentItem, isNull);
      h.service.dispose();
    });

    test('SettingsProvider.setVoice 会触发 refreshSession', () async {
      final h = await _makeService(voice: 'voiceA');
      final before = h.service.currentSession;
      await h.settings.setVoice('voiceB');
      expect(h.service.currentSession, before + 1);
      h.service.dispose();
    });

    test('play/pause 在禁用状态下可调用且不抛异常', () async {
      final h = await _makeService(storyTts: false);
      expect(h.service.isEnabled, isFalse);
      h.service.play();
      expect(h.service.isEnabled, isTrue);
      h.service.pause();
      h.service.dispose();
    });
  });

  group('TtsEngineService with Mocks', () {
    test('play 应调用 AudioPlayer.resume 和 WakeLock.enable', () async {
      final h = await _makeMockService(storyTts: false);
      h.service.play();
      expect(h.fakeAudioPlayer.resumeCalls, equals(1));
      expect(h.fakeWakeLock.enableCalls, equals(1));
      h.service.dispose();
    });

    test('pause 应调用 AudioPlayer.pause 和 WakeLock.disable', () async {
      final h = await _makeMockService(storyTts: true);
      // WakeLock 仅在“已持有”状态下才会触发 disable，先 play() 让其进入持有状态。
      h.service.play();
      h.service.pause();
      expect(h.fakeAudioPlayer.pauseCalls, equals(1));
      expect(h.fakeWakeLock.disableCalls, equals(1));
      h.service.dispose();
    });

    test('setEnabled(false) 应调用 stop 和 disable', () async {
      final h = await _makeMockService(storyTts: true);
      // 先 play() 确保 _isEnabled=true 且 WakeLock 已被持有，避免 setEnabled(false) 因状态未同步而提前 return。
      h.service.play();
      h.service.setEnabled(false);
      expect(h.fakeAudioPlayer.stopCalls, equals(1));
      expect(h.fakeWakeLock.disableCalls, equals(1));
      h.service.dispose();
    });

    test('refreshSession 应调用 AudioPlayer.stop', () async {
      final h = await _makeMockService();
      h.service.refreshSession();
      expect(h.fakeAudioPlayer.stopCalls, equals(1));
      h.service.dispose();
    });

    test('cycleSpeed 应调用 AudioPlayer.setPlaybackRate', () async {
      final h = await _makeMockService(ttsRate: 1.0);
      // 初始化阶段会设置一次 playbackRate，这里用“相对增量”断言，避免被初始化调用次数干扰。
      final beforeCalls = h.fakeAudioPlayer.setPlaybackRateCalls;
      final beforeRate = h.fakeAudioPlayer.lastPlaybackRate;
      h.service.cycleSpeed();
      expect(h.fakeAudioPlayer.setPlaybackRateCalls, equals(beforeCalls + 1));
      expect(h.fakeAudioPlayer.lastPlaybackRate, isNot(equals(beforeRate)));
      h.service.dispose();
    });

    test('dispose 应调用 AudioPlayer.dispose', () async {
      final h = await _makeMockService();
      h.service.dispose();
      expect(h.fakeAudioPlayer.disposeCalls, equals(1));
    });

    test('初始化时应设置音量', () async {
      final h = await _makeMockService(ambientVol: 0.8);
      expect(h.fakeAudioPlayer.setVolumeCalls, greaterThanOrEqualTo(1));
      expect(h.fakeAudioPlayer.lastVolume, equals(0.8));
      h.service.dispose();
    });
  });
}
