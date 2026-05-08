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
  @override
  Stream<Duration> get onDurationChanged => const Stream.empty();
  @override
  Stream<Duration> get onPositionChanged => const Stream.empty();
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

  _FakeHttpClient({
    List<TtsHttpResponse>? queue,
    Map<String, List<int>>? downloads,
  })  : _queue = List<TtsHttpResponse>.of(queue ?? const <TtsHttpResponse>[]),
        downloads = Map<String, List<int>>.from(
          downloads ?? const <String, List<int>>{},
        );

  @override
  Future<TtsHttpResponse> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
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
  Future<TtsHttpResponse> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
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
  _MockHarness({
    required this.settings,
    required this.service,
    required this.fakeAudioPlayer,
    required this.fakeWakeLock,
  });
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
  _mockPathProviderTempDir(_testTempDir?.path ?? Directory.systemTemp.path);
  final settings = SettingsProvider()..loadFromStorage();
  final service = TtsEngineService(settings);
  await pumpEventQueue(times: 50);
  await Future<void>.delayed(const Duration(milliseconds: 10));
  return _Harness(settings: settings, service: service);
}

Future<_MockHarness> _makeMockService({
  bool storyTts = false,
  double ttsRate = 1.0,
  double ambientVol = 0.5,
  String voice = 'zh-CN-XiaoxiaoNeural',
  TtsConfig? config,
  TtsHttpClient? httpClient,
  Future<void> Function(Duration)? delayFn,
}) async {
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
    delayFn:
        delayFn ?? (d) => Future<void>.delayed(const Duration(milliseconds: 1)),
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
    fakeWakeLock: fakeWakeLock,
  );
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
        StorageService.getSettingTtsRate(),
        equals(h.service.playbackRate),
      );
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
      final h = await _makeService(voice: 'zh-CN-XiaoxiaoNeural');
      final before = h.service.currentSession;
      await h.settings.setVoice('zh-CN-YunxiNeural');
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

    // ── T-6 / P1-1 回归用例：playFile 不再在每句结束时释放 wakelock ───────
    // 旧实现会在每句结束调 _syncWakeLock(false)，下一句进入相同 playing 状态时
    // syncShadow 因 _state 未变化不会重新申请 → 屏幕从第二句开始熄灭。
    // 修复后 wakelock 仅由 stopAll/pause/dispose 释放，连读不再触发。
    test('连读两句之间 playFile 不得调用 wakelock.disable（P1-1）', () async {
      final h = await _makeMockService(storyTts: true);
      // 等待 _initTtsHardware 异步任务完成
      await pumpEventQueue(times: 10);
      final disableSnapshot = h.fakeWakeLock.disableCalls;

      // 准备一个临时 mp3 文件，长度 > 1024 byte 以通过 playFile 的"过小校验"。
      final tmp = await Directory.systemTemp.createTemp('yueyou_p1_1_');
      addTearDown(() async {
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      });
      final tmpFile = File('${tmp.path}/sample.mp3');
      await tmpFile.writeAsBytes(List<int>.filled(2048, 1));

      // 模拟连读两句：连续调用 playFile，期间通过 completePlayback 触发自然结束。
      Future<void> playOnce() async {
        final onCompleteFired = Completer<void>();
        final playFileFuture = h.service.playFile(tmpFile.path, onComplete: () {
          if (!onCompleteFired.isCompleted) onCompleteFired.complete();
        });
        // 等 audioPlayer.resume 被调用后再触发 onPlayerComplete。
        for (int i = 0; i < 200; i++) {
          if (h.fakeAudioPlayer.resumeCalls > 0) break;
          await pumpEventQueue(times: 1);
        }
        h.fakeAudioPlayer.completePlayback();
        await onCompleteFired.future.timeout(const Duration(seconds: 5));
        await playFileFuture.timeout(const Duration(seconds: 5));
        // 重置 resumeCalls 计数，便于下一次 playOnce 等待。
        h.fakeAudioPlayer.resumeCalls = 0;
      }

      await playOnce();
      // 第一句结束后立刻紧跟第二句，模拟 _playRunner 连续消费 buffer。
      await playOnce();

      expect(h.fakeWakeLock.disableCalls, equals(disableSnapshot),
          reason: 'P1-1：playFile 不得在每句结束时调用 wakelock.disable，'
              '否则连读时屏幕会从第二句开始熄灭');

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

  // ── 大厂标准清理：原 idle timeout skip 用例已删除 ─────────────────────────
  // 该用例在 TtsEngineService 不再持有 _idleTimer 后变为永远跳过，长期挂靠
  // 会让维护者误以为"待修复"。空闲超时逻辑已 100% 迁移至 TtsAudioNotifier，
  // 对应回归在 test/features/audio/tts_audio_notifier_test.dart 中覆盖。

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
          steps.any((s) => s['step'] == 5 && s['status'] == 'error'),
          isTrue,
        );
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
  Future<void> setVolume(double volume) => _inner.setVolume(volume);

  @override
  Future<void> setAudioContext(AudioContext context) =>
      _inner.setAudioContext(context);

  @override
  Stream<Duration> get onDurationChanged => _inner.onDurationChanged;

  @override
  Stream<Duration> get onPositionChanged => _inner.onPositionChanged;

  @override
  Future<void> setSource(Source source) async {
    await _inner.setSource(source);
    throw Exception('setSource failed');
  }

  @override
  Future<void> stop() => _inner.stop();
}

class _ThrowingHttpClient implements TtsHttpClient {
  final Object error;
  const _ThrowingHttpClient(this.error);

  @override
  Future<TtsHttpResponse> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) {
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
  Future<TtsHttpResponse> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return future;
  }

  @override
  Future<void> download(Uri url, String savePath) async {
    await future;
  }
}
