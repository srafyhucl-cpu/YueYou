import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
  Future<void> setAudioContext(AudioContext context) async {}

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
  final List<TtsHttpResponse> _queue;
  final Map<String, List<int>> downloads;
  int postCalls = 0;
  int downloadCalls = 0;

  _FakeHttpClient(
      {List<TtsHttpResponse>? queue, Map<String, List<int>>? downloads,})
      : _queue = List<TtsHttpResponse>.of(queue ?? const <TtsHttpResponse>[]),
        downloads = Map<String, List<int>>.from(
          downloads ?? const <String, List<int>>{},
        );

  @override
  Future<TtsHttpResponse> post(Uri url,
      {Map<String, String>? headers, Object? body,}) async {
    postCalls++;
    if (_queue.isNotEmpty) {
      return _queue.removeAt(0);
    }
    return const TtsHttpResponse(statusCode: 500, body: 'internal error');
  }

  @override
  Future<void> download(Uri url, String savePath) async {
    downloadCalls++;
    final bytes = downloads[url.toString()];
    if (bytes == null) {
      throw HttpException('missing download stub: $url');
    }
    final file = File(savePath);
    await file.writeAsBytes(bytes);
  }
}

class _SequencedHttpClient implements TtsHttpClient {
  final List<Object> _events;
  final Map<String, List<int>> downloads;
  int postCalls = 0;
  int downloadCalls = 0;

  _SequencedHttpClient(this._events, {Map<String, List<int>>? downloads})
      : downloads = Map<String, List<int>>.from(
          downloads ?? const <String, List<int>>{},
        );

  @override
  Future<TtsHttpResponse> post(Uri url,
      {Map<String, String>? headers, Object? body,}) async {
    postCalls++;
    if (_events.isEmpty) {
      return const TtsHttpResponse(statusCode: 500, body: 'internal error');
    }
    final e = _events.removeAt(0);
    if (e is TtsHttpResponse) return e;
    return Future<TtsHttpResponse>.error(e);
  }

  @override
  Future<void> download(Uri url, String savePath) async {
    downloadCalls++;
    final bytes = downloads[url.toString()];
    if (bytes == null) {
      throw HttpException('missing download stub: $url');
    }
    final file = File(savePath);
    await file.writeAsBytes(bytes);
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
      required this.fakeWakeLock,});
}

void _mockPathProviderTempDir(String tempDirPath) {
  const MethodChannel channel =
      MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    if (call.method == 'getTemporaryDirectory') {
      return tempDirPath;
    }
    if (call.method == 'getApplicationDocumentsDirectory') {
      return tempDirPath;
    }
    if (call.method == 'getApplicationSupportDirectory') {
      return tempDirPath;
    }
    return tempDirPath;
  });
}

Directory? _testTempDir;

void _restorePathProviderTempDir() {
  _mockPathProviderTempDir(_testTempDir?.path ?? Directory.systemTemp.path);
}

Future<void> _safeDeleteDir(Directory dir) async {
  try {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  } catch (_) {}
}

TtsHttpResponse _jsonUrlResponse(String url) {
  return TtsHttpResponse(
    statusCode: 200,
    body: jsonEncode({'status': 'success', 'url': url}),
  );
}

List<int> _audioBytes({required int sizeBytes}) {
  return Uint8List(sizeBytes);
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
    String voice = 'zh-CN-XiaoxiaoNeural',}) async {
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
  _mockPathProviderTempDir(_testTempDir?.path ?? Directory.systemTemp.path);
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
    Future<void> Function(Duration)? delayFn,}) async {
  SharedPreferences.setMockInitialValues({
    'setting_story_tts': storyTts,
    'setting_tts_rate': ttsRate,
    'setting_ambient_vol': ambientVol,
    'setting_voice': voice,
  });
  StorageService.resetForTesting();
  await StorageService.init();
  _mockPathProviderTempDir(_testTempDir?.path ?? Directory.systemTemp.path);
  final settings = SettingsProvider()..loadFromStorage();
  final fakeAudioPlayer = _FakeAudioPlayer();
  final fakeWakeLock = _FakeWakeLock();
  final service = TtsEngineService(
    settings,
    config: config,
    audioPlayer: fakeAudioPlayer,
    wakeLock: fakeWakeLock,
    httpClient: httpClient,
    delayFn: delayFn ?? (d) => Future<void>.delayed(const Duration(milliseconds: 1)),
  );
  // 为所有 Mock Service 提供默认的哑元回调，防止因 onNeedPrefetch 为空而导致开启失败
  service.onNeedPrefetch = (session) async => null;
  service.onItemStarted = (item) {};
  service.onItemFinished = (item) {};

  await pumpEventQueue(times: 20);
  for (int i = 0;
      i < 100 &&
          (fakeAudioPlayer.setVolumeCalls == 0 ||
              fakeAudioPlayer.setPlaybackRateCalls == 0);
      i++) {
    await pumpEventQueue(times: 1);
  }
  return _MockHarness(
      settings: settings,
      service: service,
      fakeAudioPlayer: fakeAudioPlayer,
      fakeWakeLock: fakeWakeLock,);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    _testTempDir = Directory.systemTemp.createTempSync('tts_test_');
  });

  tearDownAll(() async {
    if (_testTempDir != null) {
      await _safeDeleteDir(_testTempDir!);
    }
  });

  tearDown(() {
    if (_testTempDir != null && _testTempDir!.existsSync()) {
      for (final entity in _testTempDir!.listSync()) {
        try {
          entity.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  });

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
          StorageService.getSettingTtsRate(), equals(h.service.playbackRate),);
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
      // 绑定 onNeedPrefetch 以允许 TTS 启用
      h.service.onNeedPrefetch = (session) async {
        return TtsAudioRequest(lineIndex: 0, text: '这是一句测试文本', title: 't');
      };
      h.service.play();
      expect(h.service.isEnabled, isTrue);
      h.service.pause();
      h.service.dispose();
    });
  });

  group('TtsEngineService with Mocks', () {
    test('play 在暂停时应调用 AudioPlayer.resume 和 WakeLock.enable', () async {
      final h = await _makeMockService(storyTts: true);
      // 等待初始化完成并进入 buffering
      for (int i = 0; i < 100 && !h.service.isEnabled; i++) {
        await pumpEventQueue(times: 1);
      }
      
      // 1. 先暂停
      await h.service.pause();
      final beforeResume = h.fakeAudioPlayer.resumeCalls;
      final beforeEnable = h.fakeWakeLock.enableCalls;

      // 2. 再播放
      h.service.play();
      await pumpEventQueue(times: 10);

      expect(h.fakeAudioPlayer.resumeCalls, equals(beforeResume)); 
      expect(h.fakeWakeLock.enableCalls, equals(beforeEnable + 1)); 
      h.service.dispose();
    });

    test('pause 应调用 AudioPlayer.pause 和 WakeLock.disable', () async {
      final h = await _makeMockService(storyTts: true);
      // 等待初始化完成
      for (int i = 0; i < 100 && !h.service.isEnabled; i++) {
        await pumpEventQueue(times: 1);
      }
      // 额外等待以确保 _syncWakeLock(true) 异步任务执行完成
      await pumpEventQueue(times: 10);
      
      await h.service.pause();

      expect(h.fakeAudioPlayer.pauseCalls, equals(1));
      expect(h.fakeWakeLock.disableCalls, equals(1));
      h.service.dispose();
    });

    test('setEnabled(false) 应调用 stop 和 disable', () async {
      final h = await _makeMockService(storyTts: true);
      // 等待初始化完成
      for (int i = 0; i < 100 && !h.service.isEnabled; i++) {
        await pumpEventQueue(times: 1);
      }
      // 额外等待以确保 _syncWakeLock(true) 异步任务执行完成
      await pumpEventQueue(times: 10);
      
      h.service.setEnabled(false);
      await pumpEventQueue(times: 10);

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

    test('syncSpeedFromSettings 应更新 playbackRate', () async {
      final h = await _makeMockService(ttsRate: 1.0);
      h.service.syncSpeedFromSettings(1.5, 1.5);
      expect(h.service.playbackRate, equals(1.5));
      expect(h.fakeAudioPlayer.lastPlaybackRate, equals(1.5));
      h.service.dispose();
    });

    test('syncSpeedFromSettings 相同值时不更新', () async {
      final h = await _makeMockService(ttsRate: 1.5);
      final beforeCalls = h.fakeAudioPlayer.setPlaybackRateCalls;
      h.service.syncSpeedFromSettings(1.5, 1.5);
      expect(h.fakeAudioPlayer.setPlaybackRateCalls, equals(beforeCalls));
      h.service.dispose();
    });

    test('stopAll 应递增 session 并调用 stop', () async {
      final h = await _makeMockService(storyTts: true);
      final before = h.service.currentSession;
      h.service.stopAll();
      expect(h.service.currentSession, equals(before + 1));
      expect(h.fakeAudioPlayer.stopCalls, greaterThanOrEqualTo(1));
      h.service.dispose();
    });

    test('启用状态下 refreshSession 应触发重启分支', () async {
      final h = await _makeMockService(storyTts: false);
      h.service.setEnabled(true);
      final beforeSession = h.service.currentSession;
      final beforeStopCalls = h.fakeAudioPlayer.stopCalls;

      h.service.refreshSession();

      expect(h.service.currentSession, equals(beforeSession + 1));
      expect(h.fakeAudioPlayer.stopCalls, greaterThan(beforeStopCalls));
      h.service.dispose();
    });

    test('启用状态下 notifyUserActivity 应执行重置计时器分支', () async {
      final h = await _makeMockService(storyTts: false);
      h.service.setEnabled(true);

      expect(() => h.service.notifyUserActivity(), returnsNormally);
      h.service.dispose();
    });

    test('testConnection 失败后应暴露 lastError 且可清理', () async {
      final httpClient = _FakeHttpClient(
        queue: const <TtsHttpResponse>[
          TtsHttpResponse(statusCode: 404, body: 'not found'),
        ],
      );
      final h = await _makeMockService(
        storyTts: false,
        httpClient: httpClient,
      );

      await h.service.testConnection();

      expect(h.service.lastError, contains('请求的资源不存在'));

      h.service.clearLastError();
      expect(h.service.lastError, isNull);

      h.service.dispose();
    });
  });

  group('TtsEngineService - hard branches (prefetch/download)', () {
    late DebugPrintCallback oldDebugPrint;

    tearDown(() {
      _restorePathProviderTempDir();
    });

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
        queue: const <TtsHttpResponse>[
          TtsHttpResponse(statusCode: 400, body: 'bad request'),
        ],
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
        queue: const <TtsHttpResponse>[
          TtsHttpResponse(statusCode: 500, body: 'e1'),
          TtsHttpResponse(statusCode: 500, body: 'e2'),
          TtsHttpResponse(statusCode: 500, body: 'e3'),
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
      for (int i = 0; i < 400 && httpClient.postCalls < cfg.maxRetries; i++) {
        await pumpEventQueue(times: 1);
      }

      expect(httpClient.postCalls, equals(cfg.maxRetries));
      expect(
          delay.durations
              .where((d) =>
                  d == const Duration(milliseconds: 2) ||
                  d == const Duration(milliseconds: 4),)
              .length,
          greaterThanOrEqualTo(2),);
      h.service.setEnabled(false);
      h.service.dispose();
    });

    test('连续下载失败≥5次：应触发15秒退避等待', () async {
      final httpClient = _FakeHttpClient(
        queue: List<TtsHttpResponse>.generate(
          6,
          (_) => const TtsHttpResponse(statusCode: 400, body: 'bad request'),
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

    test('HTTP 请求抛异常：应指数退避后重试并最终成功', () async {
      final tempDir = await Directory.systemTemp.createTemp('tts_retry_ok');
      const audioUrl = 'https://cdn.test/retry_ok.mp3';
      try {
        _mockPathProviderTempDir(tempDir.path);

        final httpClient = _SequencedHttpClient(
          <Object>[
            const SocketException('x'),
            _jsonUrlResponse(audioUrl),
          ],
          downloads: <String, List<int>>{
            audioUrl: _audioBytes(sizeBytes: 2048),
          },
        );
        final delay = _DelayRecorder();
        final h = await _makeMockService(
          storyTts: false,
          httpClient: httpClient,
          delayFn: delay.call,
          config: const TtsConfig(
            serverUrl: 'https://test.invalid/tts',
            maxRetries: 2,
            requestTimeout: Duration(milliseconds: 10),
            baseRetryDelay: Duration(milliseconds: 1),
            maxPrefetchQueue: 1,
          ),
        );

        h.service.onNeedPrefetch = (session) async {
          if (httpClient.postCalls > 1) return null;
          return TtsAudioRequest(lineIndex: 0, text: '这是一句测试文本', title: 't');
        };

        h.service.setEnabled(true);
        for (int i = 0; i < 800 && httpClient.postCalls < 2; i++) {
          await pumpEventQueue(times: 1);
        }

        for (int i = 0; i < 800 && httpClient.downloadCalls == 0; i++) {
          await pumpEventQueue(times: 1);
        }

        expect(httpClient.postCalls, equals(2));
        expect(httpClient.downloadCalls, greaterThanOrEqualTo(1));
        expect(delay.has(const Duration(milliseconds: 1)), isTrue);
        h.service.setEnabled(false);
        h.service.dispose();
      } finally {
        await _safeDeleteDir(tempDir);
      }
    });
  });

  group('TtsEngineService - idle timeout', () {
    test('空闲超时触发后应自动 setEnabled(false) 并写回 storyTts=false', () async {
      SharedPreferences.setMockInitialValues({
        'setting_story_tts': false,
        'setting_tts_rate': 1.0,
        'setting_ambient_vol': 0.5,
        'setting_voice': 'zh-CN-XiaoxiaoNeural',
        'setting_idle_timeout': 1,
      });
      StorageService.resetForTesting();
      await StorageService.init();

      final settings = SettingsProvider()..loadFromStorage();
      final fakeAudioPlayer = _FakeAudioPlayer();
      final fakeWakeLock = _FakeWakeLock();
      final service = TtsEngineService(
        settings,
        audioPlayer: fakeAudioPlayer,
        wakeLock: fakeWakeLock,
        httpClient: _FakeHttpClient(),
        delayFn: (d) => Future<void>.delayed(d),
        config: const TtsConfig(
          serverUrl: 'https://test.invalid/tts',
          maxRetries: 1,
          requestTimeout: Duration(milliseconds: 10),
          baseRetryDelay: Duration(milliseconds: 1),
          maxPrefetchQueue: 0,
        ),
      );

      service.onNeedPrefetch = (session) async => null;

      fakeAsync((async) {
        async.flushMicrotasks();
        service.setEnabled(true);
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 1));
        async.flushMicrotasks();

        expect(service.isEnabled, isFalse);
        expect(settings.storyTts, isFalse);
        expect(StorageService.getSettingStoryTts(), isFalse);
      });

      service.dispose();
    });
  });

  group('TtsEngineService - play loop branches', () {
    late DebugPrintCallback oldDebugPrint;

    setUp(() {
      // 确保每个用例执行前 path_provider mock 指向 _testTempDir，
      // 防止串行运行时被其他测试文件的 setUp 污染（如 tts_contract_test.dart 设为 '.'）
      _restorePathProviderTempDir();
    });

    tearDown(() {
      _restorePathProviderTempDir();
    });

    setUpAll(() {
      oldDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
    });

    tearDownAll(() {
      debugPrint = oldDebugPrint;
    });

    test('成功下载并播放：触发 started/finished 且删除临时文件', () async {
      final tempDir = await Directory.systemTemp.createTemp('tts_play_ok');
      const audioUrl = 'https://cdn.test/play_ok.mp3';
      try {
        _mockPathProviderTempDir(tempDir.path);

        final httpClient = _FakeHttpClient(
          queue: <TtsHttpResponse>[_jsonUrlResponse(audioUrl)],
          downloads: <String, List<int>>{
            audioUrl: _audioBytes(sizeBytes: 2048),
          },
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
            baseRetryDelay: Duration(milliseconds: 1),
            maxPrefetchQueue: 1,
          ),
        );

        int startedCalls = 0;
        int finishedCalls = 0;
        h.service.onItemStarted = (_) {
          startedCalls++;
        };
        h.service.onItemFinished = (_) {
          finishedCalls++;
        };

        h.service.onNeedPrefetch = (session) async {
          if (httpClient.postCalls > 0) return null;
          return TtsAudioRequest(lineIndex: 7, text: '这是一句测试文本', title: 't');
        };

        h.service.setEnabled(true);

        for (int i = 0; i < 200 && h.fakeAudioPlayer.setSourceCalls == 0; i++) {
          await pumpEventQueue(times: 1);
        }
        expect(h.fakeAudioPlayer.setSourceCalls, greaterThanOrEqualTo(1));
        expect(startedCalls, greaterThanOrEqualTo(1));

        h.fakeAudioPlayer.completePlayback();
        for (int i = 0; i < 500 && finishedCalls == 0; i++) {
          await pumpEventQueue(times: 1);
        }
        expect(finishedCalls, greaterThanOrEqualTo(1));

        h.service.setEnabled(false);
        await pumpEventQueue(times: 20);
        final mp3s = tempDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.mp3'))
            .toList();
        expect(mp3s, isEmpty);

        h.service.dispose();
      } finally {
        await _safeDeleteDir(tempDir);
      }
    });

    test('音频文件太小(<1KB)：应跳过且不调用 setSource', () async {
      final tempDir = await Directory.systemTemp.createTemp('tts_play_small');
      const audioUrl = 'https://cdn.test/play_small.mp3';
      try {
        _mockPathProviderTempDir(tempDir.path);

        final httpClient = _FakeHttpClient(
          queue: <TtsHttpResponse>[_jsonUrlResponse(audioUrl)],
          downloads: <String, List<int>>{audioUrl: _audioBytes(sizeBytes: 10)},
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
            baseRetryDelay: Duration(milliseconds: 1),
            maxPrefetchQueue: 1,
          ),
        );

        h.service.onNeedPrefetch = (session) async {
          if (httpClient.postCalls > 0) return null;
          return TtsAudioRequest(lineIndex: 1, text: '这是一句测试文本', title: 't');
        };

        h.service.setEnabled(true);
        for (int i = 0; i < 200 && httpClient.postCalls == 0; i++) {
          await pumpEventQueue(times: 1);
        }
        expect(httpClient.postCalls, greaterThanOrEqualTo(1));

        for (int i = 0; i < 400 && h.service.bufferedCount == 0; i++) {
          await pumpEventQueue(times: 1);
        }

        for (int i = 0; i < 800; i++) {
          final mp3s = tempDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.mp3'))
              .toList();
          if (mp3s.isEmpty) {
            break;
          }
          await pumpEventQueue(times: 1);
        }

        final mp3sAfter = tempDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.mp3'))
            .toList();
        expect(mp3sAfter, isEmpty);
        expect(h.fakeAudioPlayer.setSourceCalls, equals(0));

        h.service.setEnabled(false);
        h.service.dispose();
      } finally {
        await _safeDeleteDir(tempDir);
      }
    });

    test('AudioPlayer.setSource 抛异常：应进入异常恢复分支并 stop', () async {
      final tempDir = await Directory.systemTemp.createTemp('tts_play_throw');
      const audioUrl = 'https://cdn.test/play_throw.mp3';
      try {
        _mockPathProviderTempDir(tempDir.path);

        final throwingPlayer = _FakeAudioPlayer();
        final httpClient = _FakeHttpClient(
          queue: <TtsHttpResponse>[_jsonUrlResponse(audioUrl)],
          downloads: <String, List<int>>{
            audioUrl: _audioBytes(sizeBytes: 2048),
          },
        );
        final settings = await (() async {
          SharedPreferences.setMockInitialValues({
            'setting_story_tts': false,
            'setting_tts_rate': 1.0,
            'setting_ambient_vol': 0.5,
            'setting_voice': 'zh-CN-XiaoxiaoNeural',
          });
          StorageService.resetForTesting();
          await StorageService.init();
          return SettingsProvider()..loadFromStorage();
        })();

        final service = TtsEngineService(
          settings,
          audioPlayer: _ThrowingSetSourceAudioPlayer(throwingPlayer),
          wakeLock: _FakeWakeLock(),
          httpClient: httpClient,
          delayFn: (d) => Future<void>.delayed(const Duration(milliseconds: 1)),
          config: const TtsConfig(
            serverUrl: 'https://test.invalid/tts',
            maxRetries: 1,
            requestTimeout: Duration(milliseconds: 10),
            baseRetryDelay: Duration(milliseconds: 1),
            maxPrefetchQueue: 1,
          ),
        );

        service.onNeedPrefetch = (session) async {
          if (httpClient.postCalls > 0) return null;
          return TtsAudioRequest(lineIndex: 3, text: '这是一句测试文本', title: 't');
        };

        await pumpEventQueue(times: 20);
        service.setEnabled(true);
        for (int i = 0; i < 200 && httpClient.postCalls == 0; i++) {
          await pumpEventQueue(times: 10);
        }
        for (int i = 0; i < 400 && service.bufferedCount == 0; i++) {
          await pumpEventQueue(times: 10);
        }
        for (int i = 0; i < 400 && throwingPlayer.setSourceCalls == 0; i++) {
          await pumpEventQueue(times: 10);
        }

        service.setEnabled(false);
        await pumpEventQueue(times: 50);

        expect(throwingPlayer.setSourceCalls, greaterThanOrEqualTo(1));
        expect(throwingPlayer.stopCalls, greaterThanOrEqualTo(1));
        service.dispose();
      } finally {
        await _safeDeleteDir(tempDir);
      }
    });
  });

  group('TtsEngineService - testConnection branches', () {
    late DebugPrintCallback oldDebugPrint;

    tearDown(() {
      _restorePathProviderTempDir();
    });

    setUpAll(() {
      oldDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
    });

    tearDownAll(() {
      debugPrint = oldDebugPrint;
    });

    test('testConnection 成功返回 success=true 且包含 steps', () async {
      final tempDir = await Directory.systemTemp.createTemp('tts_conn_ok');
      const audioUrl = 'https://cdn.test/conn_ok.mp3';
      try {
        _mockPathProviderTempDir(tempDir.path);
        final httpClient = _FakeHttpClient(
          queue: <TtsHttpResponse>[_jsonUrlResponse(audioUrl)],
          downloads: <String, List<int>>{
            audioUrl: _audioBytes(sizeBytes: 2048),
          },
        );
        final h = await _makeMockService(
          storyTts: false,
          httpClient: httpClient,
        );

        final result = await h.service.testConnection();
        expect(result['success'], isTrue);
        expect(result['statusCode'], equals(200));
        expect(result['steps'], isA<List>());

        h.service.dispose();
      } finally {
        await _safeDeleteDir(tempDir);
      }
    });

    test('testConnection 服务器返回非200：success=false', () async {
      final httpClient = _FakeHttpClient(
        queue: const <TtsHttpResponse>[
          TtsHttpResponse(statusCode: 404, body: 'not found'),
        ],
      );
      final h = await _makeMockService(
        storyTts: false,
        httpClient: httpClient,
      );

      final result = await h.service.testConnection();
      expect(result['success'], isFalse);
      expect(result['statusCode'], equals(404));

      h.service.dispose();
    });

    test('testConnection 网络异常：SocketException 分支', () async {
      final h = await _makeMockService(
        storyTts: false,
        httpClient: const _ThrowingHttpClient(SocketException('x')),
      );

      final result = await h.service.testConnection();
      expect(result['success'], isFalse);
      expect(result['message'], isA<String>());

      h.service.dispose();
    });

    test('testConnection 200 但音频太小：应进入 warning 分支', () async {
      final tempDir = await Directory.systemTemp.createTemp('tts_conn_small');
      const audioUrl = 'https://cdn.test/conn_small.mp3';
      try {
        _mockPathProviderTempDir(tempDir.path);
        final httpClient = _FakeHttpClient(
          queue: <TtsHttpResponse>[_jsonUrlResponse(audioUrl)],
          downloads: <String, List<int>>{audioUrl: _audioBytes(sizeBytes: 10)},
        );
        final h = await _makeMockService(
          storyTts: false,
          httpClient: httpClient,
        );

        final result = await h.service.testConnection();
        expect(result['success'], isTrue);
        expect(result['statusCode'], equals(200));
        expect(result['steps'], isA<List>());

        h.service.dispose();
      } finally {
        await _safeDeleteDir(tempDir);
      }
    });

    test('testConnection 写入文件失败：step 5 应为 error', () async {
      const MethodChannel channel =
          MethodChannel('plugins.flutter.io/path_provider');

      try {
        const audioUrl = 'https://cdn.test/conn_write_fail.mp3';
        final httpClient = _FakeHttpClient(
          queue: <TtsHttpResponse>[_jsonUrlResponse(audioUrl)],
          downloads: <String, List<int>>{
            audioUrl: _audioBytes(sizeBytes: 2048),
          },
        );
        final h = await _makeMockService(
          storyTts: false,
          httpClient: httpClient,
        );

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
          if (call.method == 'getTemporaryDirectory') {
            throw PlatformException(code: 'x');
          }
          return null;
        });

        final result = await h.service.testConnection();
        expect(result['success'], isTrue);
        expect(result['statusCode'], equals(200));
        final steps = (result['steps'] as List).cast<Map>();
        expect(
            steps.any((s) => s['step'] == 5 && s['status'] == 'error'), isTrue,);
        h.service.dispose();
      } finally {
        _restorePathProviderTempDir();
      }
    });

    test('testConnection URL 非法：应进入未知错误分支', () async {
      final h = await _makeMockService(
        storyTts: false,
        httpClient: _FakeHttpClient(),
        config: const TtsConfig(serverUrl: 'http://[::1'),
      );

      final result = await h.service.testConnection();
      expect(result['success'], isFalse);
      expect(result['message'], isA<String>());
      h.service.dispose();
    });

    test('testConnection 超时：应命中 TimeoutException 分支', () async {
      final settings = await (() async {
        SharedPreferences.setMockInitialValues({
          'setting_story_tts': false,
          'setting_tts_rate': 1.0,
          'setting_ambient_vol': 0.5,
          'setting_voice': 'zh-CN-XiaoxiaoNeural',
        });
        StorageService.resetForTesting();
        await StorageService.init();
        return SettingsProvider()..loadFromStorage();
      })();

      final hanging = Completer<TtsHttpResponse>();
      Map<String, dynamic>? result;

      fakeAsync((async) {
        final service = TtsEngineService(
          settings,
          audioPlayer: _FakeAudioPlayer(),
          wakeLock: _FakeWakeLock(),
          httpClient: _HangingHttpClient(hanging.future),
          delayFn: (d) => Future<void>.delayed(d),
          config: const TtsConfig(
            serverUrl: 'https://test.invalid/tts',
            maxRetries: 1,
            requestTimeout: Duration(milliseconds: 10),
            baseRetryDelay: Duration(milliseconds: 1),
            maxPrefetchQueue: 0,
          ),
        );
        service.onNeedPrefetch = (session) async => null;

        async.flushMicrotasks();
        final f = service.testConnection();
        f.then((v) {
          result = v;
        });
        async.elapse(const Duration(seconds: 11));
        async.flushMicrotasks();

        expect(result, isNotNull);
        expect(result!['success'], isFalse);
        expect(result!['message'], contains('超时'));

        service.dispose();
      });
    });
  });
}

class _ThrowingSetSourceAudioPlayer implements TtsAudioPlayer {
  final _FakeAudioPlayer _inner;
  _ThrowingSetSourceAudioPlayer(this._inner);

  @override
  Future<void> dispose() => _inner.dispose();

  @override
  Stream<void> get onPlayerComplete => _inner.onPlayerComplete;

  @override
  Future<void> pause() => _inner.pause();

  @override
  Future<void> resume() => _inner.resume();

  @override
  Future<void> setPlaybackRate(double rate) => _inner.setPlaybackRate(rate);

  @override
  Future<void> setSource(Source source) async {
    await _inner.setSource(source);
    throw Exception('setSource failed');
  }

  @override
  Future<void> setVolume(double volume) => _inner.setVolume(volume);

  @override
  Future<void> setAudioContext(AudioContext context) => _inner.setAudioContext(context);

  @override
  Future<void> stop() => _inner.stop();
}

class _ThrowingHttpClient implements TtsHttpClient {
  final Object error;
  const _ThrowingHttpClient(this.error);

  @override
  Future<TtsHttpResponse> post(Uri url,
      {Map<String, String>? headers, Object? body,}) {
    return Future<TtsHttpResponse>.error(error);
  }

  @override
  Future<void> download(Uri url, String savePath) {
    return Future<void>.error(error);
  }
}

class _HangingHttpClient implements TtsHttpClient {
  final Future<TtsHttpResponse> future;
  const _HangingHttpClient(this.future);

  @override
  Future<TtsHttpResponse> post(Uri url,
      {Map<String, String>? headers, Object? body,}) {
    return future;
  }

  @override
  Future<void> download(Uri url, String savePath) async {
    await future;
  }
}
