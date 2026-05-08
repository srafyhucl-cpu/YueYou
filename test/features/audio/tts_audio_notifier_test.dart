import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/core/config/tts_config.dart';
import 'package:yueyou/features/audio/domain/tts_audio_state.dart';
import 'package:yueyou/features/audio/providers/tts_audio_notifier.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';

import '../../utils/test_utils.dart';

class _ControllableAudioPlayer implements TtsAudioPlayer {
  int stopCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;

  @override
  Future<void> setSource(Source source) async {}

  @override
  Future<void> resume() async {
    resumeCalls++;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setPlaybackRate(double rate) async {}

  @override
  Future<void> setAudioContext(AudioContext context) async {}

  @override
  Stream<void> get onPlayerComplete => const Stream<void>.empty();

  @override
  Stream<Duration> get onPositionChanged => const Stream<Duration>.empty();

  @override
  Stream<Duration> get onDurationChanged => const Stream<Duration>.empty();

  @override
  Future<void> dispose() async {}
}

class _SingleAudioHttpClient implements TtsHttpClient {
  int postCalls = 0;
  int downloadCalls = 0;
  // P0-4 回归用：记录所有下载落盘的文件路径，便于检查"暂停期间文件未被删"。
  final List<String> downloadedPaths = [];

  @override
  Future<TtsHttpResponse> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    postCalls++;
    return const TtsHttpResponse(
      statusCode: 200,
      body: '{"status":"success","url":"https://cdn.test/audio.mp3"}',
    );
  }

  @override
  Future<void> download(Uri url, String savePath) async {
    downloadCalls++;
    downloadedPaths.add(savePath);
    await File(savePath).writeAsBytes(List<int>.filled(2048, 1));
  }
}

class _OneShotSentenceSource implements TtsSentenceSource {
  int nextCalls = 0;
  int startedCalls = 0;
  int finishedCalls = 0;

  @override
  Future<TtsAudioRequest?> nextTtsSentence(int session) async {
    nextCalls++;
    if (nextCalls > 1) return null;
    return TtsAudioRequest(
      lineIndex: 0,
      endLineIndex: 0,
      text: '这是一句用于暂停测试的文本',
      title: '测试章节',
    );
  }

  @override
  FutureOr<void> onTtsItemStarted(TtsAudioItem item) {
    startedCalls++;
  }

  @override
  FutureOr<void> onTtsItemFinished(TtsAudioItem item) {
    finishedCalls++;
  }

  @override
  void resetFetchIndex() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pause 中断 playFile 完成回调时不推进句子', () async {
    await initializeTestEnvironment();
    final settings = makeSettings();
    final player = _ControllableAudioPlayer();
    final httpClient = _SingleAudioHttpClient();
    final engine = TtsEngineService(
      settings,
      config: const TtsConfig(
        serverUrl: 'https://test.invalid/tts',
        maxPrefetchQueue: 1,
        requestTimeout: Duration(milliseconds: 50),
        baseRetryDelay: Duration(milliseconds: 1),
      ),
      audioPlayer: player,
      wakeLock: FakeWakeLock(),
      httpClient: httpClient,
      fallbackEngine: FakeFallbackEngine(),
      delayFn: (duration) =>
          Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    final container = ProviderContainer(
      overrides: [
        ttsEngineProvider.overrideWith((ref) => engine),
        settingsProvider.overrideWith((ref) => settings),
      ],
    );
    addTearDown(() {
      container.dispose();
      engine.dispose();
    });

    final notifier = container.read(ttsAudioProvider.notifier);
    final source = _OneShotSentenceSource();
    notifier.registerSentenceSource(source);
    notifier.play();

    // 等待引擎初始化完成并触发 onTtsItemStarted（最多 5s）
    for (int i = 0; i < 500 && source.startedCalls < 1; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(container.read(ttsAudioProvider), isA<TtsAudioPlaying>());
    expect(source.startedCalls, greaterThanOrEqualTo(1));

    await notifier.pause();
    await pumpEventQueue(times: 50);

    expect(container.read(ttsAudioProvider), isA<TtsAudioPaused>());
    expect(source.finishedCalls, 0);
    expect(player.stopCalls, greaterThanOrEqualTo(1));
    expect(player.pauseCalls, greaterThanOrEqualTo(1));
  });

  // ── T-1 / P0-4 回归用例：暂停后的临时文件不得被阅后即焚 ──────────────────
  // 旧实现：_playNext 在 await playFile 返回后无条件 _deleteFile，
  // 暂停触发的 stopAudio 会让 playFile 提前返回 → 文件被删 → resume 时跳句。
  // 修复后：_currentFilePath 仍指向当前文件即视为"暂停中断"，跳过删除。
  test('暂停后保留当前 mp3 文件供 resume 复用，杜绝跳句', () async {
    await initializeTestEnvironment();
    final settings = makeSettings();
    final player = _ControllableAudioPlayer();
    final httpClient = _SingleAudioHttpClient();
    final engine = TtsEngineService(
      settings,
      config: const TtsConfig(
        serverUrl: 'https://test.invalid/tts',
        maxPrefetchQueue: 1,
        requestTimeout: Duration(milliseconds: 50),
        baseRetryDelay: Duration(milliseconds: 1),
      ),
      audioPlayer: player,
      wakeLock: FakeWakeLock(),
      httpClient: httpClient,
      fallbackEngine: FakeFallbackEngine(),
      delayFn: (duration) =>
          Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    final container = ProviderContainer(
      overrides: [
        ttsEngineProvider.overrideWith((ref) => engine),
        settingsProvider.overrideWith((ref) => settings),
      ],
    );
    addTearDown(() {
      container.dispose();
      engine.dispose();
    });

    final notifier = container.read(ttsAudioProvider.notifier);
    final source = _OneShotSentenceSource();
    notifier.registerSentenceSource(source);
    notifier.play();

    // 等播放进入 Playing 状态
    for (int i = 0; i < 500 && source.startedCalls < 1; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(container.read(ttsAudioProvider), isA<TtsAudioPlaying>());
    expect(httpClient.downloadedPaths, isNotEmpty, reason: '播放前必须已经完成 mp3 下载');

    // 触发暂停 → stopAudio 强制 complete _playCompleter → _playNext 返回 →
    // 进入 P0-4 守卫分支：_currentFilePath == item.filePath，跳过 _deleteFile。
    await notifier.pause();
    await pumpEventQueue(times: 100);

    expect(container.read(ttsAudioProvider), isA<TtsAudioPaused>());
    expect(source.finishedCalls, 0,
        reason: '暂停期间 onTtsItemFinished 绝不能被调用，否则游标会跳句');

    // 关键断言：暂停后，已下载的 mp3 文件必须仍在磁盘上，
    // 这是 resume 时 _buffer.prepend(_currentFilePath) 重播能成功的前提。
    final pausedFile = File(httpClient.downloadedPaths.last);
    expect(pausedFile.existsSync(), isTrue,
        reason: 'P0-4：暂停后当前句的 mp3 文件不得被 _playNext 阅后即焚');
  });
}
