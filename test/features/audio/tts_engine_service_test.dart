import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/config/tts_config.dart';
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

class _FakeHttpClient implements TtsHttpClient {
  final List<http.Response> _queue;
  int postCalls = 0;

  _FakeHttpClient({List<http.Response>? queue})
      : _queue = queue ?? <http.Response>[];

  @override
  Future<http.Response> post(Uri url,
      {Map<String, String>? headers, Object? body}) async {
    postCalls++;
    if (_queue.isNotEmpty) {
      return _queue.removeAt(0);
    }
    return http.Response('internal error', 500);
  }
}

class _DelayRecorder {
  final List<Duration> durations = <Duration>[];
  int calls = 0;
  final Map<Duration, Completer<void>> _completers =
      <Duration, Completer<void>>{};

  Future<void> call(Duration d) async {
    durations.add(d);
    calls++;
    final completer = _completers[d];
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }

  bool has(Duration d) => durations.contains(d);

  Future<void> wait(Duration d) {
    return (_completers[d] ??= Completer<void>()).future;
  }
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
    String voice = 'zh-CN-XiaoxiaoNeural',
    TtsConfig? config,
    TtsHttpClient? httpClient,
    Future<void> Function(Duration)? delayFn}) async {
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
  final service = TtsEngineService(
    settings,
    config: config,
    audioPlayer: fakeAudioPlayer,
    wakeLock: fakeWakeLock,
    httpClient: httpClient,
    delayFn: delayFn,
  );
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
      h.service.play();
      h.service.pause();
      expect(h.fakeAudioPlayer.pauseCalls, equals(1));
      expect(h.fakeWakeLock.disableCalls, equals(1));
      h.service.dispose();
    });

    test('setEnabled(false) 应调用 stop 和 disable', () async {
      final h = await _makeMockService(storyTts: true);
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

  group('TtsEngineService - hard branches (prefetch/download)', () {
    late DebugPrintCallback oldDebugPrint;

    setUpAll(() {
      oldDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
    });

    tearDownAll(() {
      debugPrint = oldDebugPrint;
    });

    test('短句(<5字符)应被过滤：不触发 HTTP 请求且不入队', () async {
      final httpClient = _FakeHttpClient();
      final delay = _DelayRecorder();
      final h = await _makeMockService(
        storyTts: false,
        httpClient: httpClient,
        delayFn: delay.call,
      );

      int calls = 0;
      h.service.onNeedPrefetch = (session) async {
        calls++;
        if (calls == 1) {
          return TtsAudioRequest(lineIndex: 0, text: '啊', title: 't');
        }
        return null;
      };

      h.service.setEnabled(true);
      await delay.wait(const Duration(seconds: 1));

      expect(httpClient.postCalls, equals(0));
      expect(h.service.bufferedCount, equals(0));
      h.service.setEnabled(false);
      h.service.dispose();
    });

    test('HTTP 400：应直接跳过不重试（post 仅 1 次）', () async {
      final httpClient = _FakeHttpClient(
        queue: <http.Response>[http.Response('bad request', 400)],
      );
      final delay = _DelayRecorder();
      final h = await _makeMockService(
        storyTts: false,
        httpClient: httpClient,
        delayFn: delay.call,
        config: const TtsConfig(
          serverUrl: 'https://test.invalid/tts',
          maxRetries: 5,
          requestTimeout: Duration(milliseconds: 10),
          baseRetryDelay: Duration(milliseconds: 2),
        ),
      );

      int calls = 0;
      h.service.onNeedPrefetch = (session) async {
        calls++;
        if (calls == 1) {
          return TtsAudioRequest(lineIndex: 0, text: '一二三四五', title: 't');
        }
        return null;
      };

      h.service.setEnabled(true);
      await delay.wait(const Duration(seconds: 3));

      expect(httpClient.postCalls, equals(1));
      expect(delay.has(const Duration(seconds: 3)), isTrue);
      h.service.setEnabled(false);
      h.service.dispose();
    });

    test('HTTP 500：应按 maxRetries 重试（post 次数= maxRetries）', () async {
      const cfg = TtsConfig(
        serverUrl: 'https://test.invalid/tts',
        maxRetries: 3,
        requestTimeout: Duration(milliseconds: 10),
        baseRetryDelay: Duration(milliseconds: 2),
      );
      final httpClient = _FakeHttpClient(
        queue: <http.Response>[
          http.Response('e1', 500),
          http.Response('e2', 500),
          http.Response('e3', 500),
        ],
      );
      final delay = _DelayRecorder();
      final h = await _makeMockService(
        storyTts: false,
        httpClient: httpClient,
        delayFn: delay.call,
        config: cfg,
      );

      int calls = 0;
      h.service.onNeedPrefetch = (session) async {
        calls++;
        if (calls == 1) {
          return TtsAudioRequest(lineIndex: 0, text: '一二三四五', title: 't');
        }
        return null;
      };

      h.service.setEnabled(true);
      await delay.wait(const Duration(seconds: 3));

      expect(httpClient.postCalls, equals(cfg.maxRetries));
      expect(delay.has(const Duration(seconds: 3)), isTrue);
      h.service.setEnabled(false);
      h.service.dispose();
    });

    test('连续下载失败≥5次：应触发15秒退避等待', () async {
      final httpClient = _FakeHttpClient(
        queue: List<http.Response>.generate(
          6,
          (_) => http.Response('bad request', 400),
        ),
      );
      final delay = _DelayRecorder();
      final h = await _makeMockService(
        storyTts: false,
        httpClient: httpClient,
        delayFn: delay.call,
        config: const TtsConfig(
          serverUrl: 'https://test.invalid/tts',
          maxRetries: 1,
          requestTimeout: Duration(milliseconds: 10),
          baseRetryDelay: Duration(milliseconds: 2),
        ),
      );

      h.service.onNeedPrefetch = (session) async {
        if (httpClient.postCalls >= 5) return null;
        return TtsAudioRequest(lineIndex: 0, text: '一二三四五', title: 't');
      };

      h.service.setEnabled(true);
      await delay.wait(const Duration(seconds: 15));

      expect(httpClient.postCalls, greaterThanOrEqualTo(5));
      expect(delay.has(const Duration(seconds: 15)), isTrue);
      h.service.setEnabled(false);
      h.service.dispose();
    });
  });
}
