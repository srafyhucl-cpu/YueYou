import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';

class _Harness {
  final SettingsProvider settings;
  final TtsEngineService service;

  _Harness({required this.settings, required this.service});
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

Future<_Harness> _makeService({
  bool storyTts = false,
  double ttsRate = 1.0,
  double ambientVol = 0.5,
  String voice = 'zh-CN-XiaoxiaoNeural',
}) async {
  SharedPreferences.setMockInitialValues({
    'setting_story_tts': storyTts,
    'setting_tts_rate': ttsRate,
    'setting_ambient_vol': ambientVol,
    'setting_voice': voice,
  });
  StorageService.resetForTesting();
  await StorageService.init();

  _mockAudioplayersChannels();
  _mockWakelockPlusChannel();

  final settings = SettingsProvider();
  settings.loadFromStorage();

  final service = TtsEngineService(settings);
  await Future<void>.delayed(Duration.zero);
  return _Harness(settings: settings, service: service);
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
}
