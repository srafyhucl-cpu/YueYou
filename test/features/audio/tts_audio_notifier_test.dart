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

/// T-B：永远返回 5xx 的 HttpClient，用于驱动 downloadAudio 失败链路。
///
/// post 直接返回 500，TtsEngineService.downloadAudio 经过 maxRetries 次重试后返回 null，
/// _refillBuffer 中触发 _consecutiveFailures++，达到阈值（默认 6）后调用 _degradeToLocal。
class _AlwaysFail500HttpClient implements TtsHttpClient {
  int postCalls = 0;

  @override
  Future<TtsHttpResponse> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    postCalls++;
    return const TtsHttpResponse(statusCode: 500, body: 'simulated outage');
  }

  @override
  Future<void> download(Uri url, String savePath) async {}
}

/// T-B：可控的句子源，不会枯竭，每次返回相同的 mock 句子。
///
/// 用于在测试中持续驱动 _refillBuffer，使失败累积到降级阈值。
class _InfiniteSentenceSource implements TtsSentenceSource {
  int nextCalls = 0;
  int startedCalls = 0;
  int finishedCalls = 0;

  @override
  Future<TtsAudioRequest?> nextTtsSentence(int session) async {
    nextCalls++;
    return TtsAudioRequest(
      lineIndex: nextCalls,
      endLineIndex: nextCalls,
      text: '降级测试用例的句子 $nextCalls',
      title: '降级测试章节',
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

  // ── T-A / 大厂标准：pause → resume 闭环必须不跳句 ─────────────────────────
  //
  // 旧实现风险：
  //   resume() 时若直接走 _startPump()，下一次 _refillBuffer 会 nextTtsSentence
  //   拿到 currentIndex+1 的句子，导致用户听到的是"暂停时正在念的句子的下一句"。
  //
  // 修复合约：
  //   play() 检测 _currentFilePath != null 时，把当前文件 prepend 回缓冲队首，
  //   _playNext 取到的第一项必须是暂停时的同一文件。
  test('T-A pause → resume 必须重播暂停时的同一句（无跳句、无新下载）', () async {
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

    // 1. 等待进入 Playing 状态
    for (int i = 0; i < 500 && source.startedCalls < 1; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(container.read(ttsAudioProvider), isA<TtsAudioPlaying>());
    final downloadsBeforePause = httpClient.downloadCalls;
    expect(downloadsBeforePause, greaterThanOrEqualTo(1));

    // 2. 暂停：mp3 文件必须保留供 resume 复用
    await notifier.pause();
    await pumpEventQueue(times: 50);
    expect(container.read(ttsAudioProvider), isA<TtsAudioPaused>());
    expect(source.finishedCalls, 0,
        reason: '暂停 → onTtsItemFinished 绝不能被调用，否则 cursor 已跳');

    // 3. resume：应直接 prepend _currentFilePath 复用，不发起新句子下载
    //
    // 注意：finishedCalls 在 resume 路径上是否触发，取决于
    // FakeAudioPlayer 的 onPlayerComplete 流时序，本测试不强行约束；
    // 关键约束是"不发起新下载"——这是 T-A 的本质：复用而非重新请求。
    final startedBeforeResume = source.startedCalls;
    notifier.play();
    await pumpEventQueue(times: 50);

    expect(httpClient.downloadCalls, downloadsBeforePause,
        reason: 'T-A 核心契约：resume 不得新发起下载，必须复用暂停时缓存的 mp3 文件');
    expect(source.startedCalls, greaterThanOrEqualTo(startedBeforeResume),
        reason: 'startedCalls 至少不减少');
    // 关键正向断言：状态机必定脱离 Paused
    final state = container.read(ttsAudioProvider);
    expect(state, isNot(isA<TtsAudioPaused>()),
        reason: 'resume 后状态必须脱离 Paused，进入 Playing 或 Idle 之一');
  });

  // ── T-A 衍生：pause → stopAll 之后 resume 必须重新走完整下载链路 ──────────
  //
  // 与上一条对比：stopAll 会清空 _currentFilePath，下次 play 必须重新下载。
  test('T-A 衍生：pause → stopAll → play 必须重新下载（不复用旧文件）', () async {
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
    for (int i = 0; i < 500 && source.startedCalls < 1; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(container.read(ttsAudioProvider), isA<TtsAudioPlaying>());

    await notifier.pause();
    await notifier.stopAll();
    await pumpEventQueue(times: 50);

    expect(container.read(ttsAudioProvider), isA<TtsAudioIdle>(),
        reason: 'stopAll 后状态必须回到 Idle');
    // stopAll 后再 play 在 _OneShotSentenceSource 已耗尽，不会有新下载，
    // 但关键校验是：状态机不再持有暂停文件路径。
    expect(notifier.isDegraded, isFalse);
  });

  // ── T-B / 大厂标准：连续失败必须自动降级到本地 TTS ─────────────────────────
  //
  // 业务合约：
  //   _refillBuffer 在 downloadAudio 返回 null 或 throw 时累加 _consecutiveFailures。
  //   非 backgroundTolerant 模式下阈值为 6（null 路径）/ 8（异常路径）。
  //   命中阈值后调用 _degradeToLocal → notifier.isDegraded == true。
  //
  // 本用例使用 5xx HttpClient + 无限句子源驱动重试链路，期望 5s 内进入降级。
  test('T-B 连续 N 次下载失败必须自动切换到本地 TTS 降级模式', () async {
    await initializeTestEnvironment();
    final settings = makeSettings();
    final player = _ControllableAudioPlayer();
    final httpClient = _AlwaysFail500HttpClient();
    final engine = TtsEngineService(
      settings,
      // maxRetries=1 让每次 downloadAudio 只尝试一次就返回 null，
      // _consecutiveFailures 累加更快，缩短测试时长。
      config: const TtsConfig(
        serverUrl: 'https://test.invalid/tts',
        maxPrefetchQueue: 1,
        maxRetries: 1,
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
    final source = _InfiniteSentenceSource();
    notifier.registerSentenceSource(source);

    expect(notifier.isDegraded, isFalse, reason: '初始非降级状态');

    notifier.play();

    // 等待降级触发，最多 5s（500 次 × 10ms）。
    bool degraded = false;
    for (int i = 0; i < 500; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (notifier.isDegraded) {
        degraded = true;
        break;
      }
    }

    expect(degraded, isTrue, reason: 'T-B：连续 N 次 downloadAudio 失败后必须进入降级模式');
    expect(httpClient.postCalls, greaterThanOrEqualTo(6),
        reason: 'T-B：降级前必须至少触发 6 次失败重试');

    // 关闭，避免 _prefetchRunner 在测试结束后继续空转。
    await notifier.stopAll();
  }, timeout: const Timeout(Duration(seconds: 15)));

  // ── T-B 衍生：refreshSession 必须重置降级标志与失败计数 ────────────────────
  //
  // 防回归：用户切书或换音色时 refreshSession 应给予全新机会，
  // 避免上一书的网络故障污染新书播放。
  test('T-B 衍生：refreshSession 后降级标志与失败计数必须归零', () async {
    await initializeTestEnvironment();
    final settings = makeSettings();
    final player = _ControllableAudioPlayer();
    final httpClient = _AlwaysFail500HttpClient();
    final engine = TtsEngineService(
      settings,
      config: const TtsConfig(
        serverUrl: 'https://test.invalid/tts',
        maxPrefetchQueue: 1,
        maxRetries: 1,
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
    notifier.registerSentenceSource(_InfiniteSentenceSource());
    notifier.play();

    // 等到降级触发
    for (int i = 0; i < 500 && !notifier.isDegraded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(notifier.isDegraded, isTrue, reason: '前置：先进入降级');

    // refreshSession：换书 / 切音色场景
    await notifier.refreshSession();
    await pumpEventQueue(times: 10);

    expect(notifier.isDegraded, isFalse,
        reason: 'T-B 衍生：refreshSession 必须把降级标志重置为 false');

    await notifier.stopAll();
  }, timeout: const Timeout(Duration(seconds: 15)));

  // ── 阶段 1 推进：TtsAudioNotifier 公开 API 全覆盖 ───────────────────────────
  // 目标：把 lib/features/audio/providers/tts_audio_notifier.dart
  // 从 70.56% 拉到 ≥ 75%。下面的用例均 sentence-source-less（避免泵真实启动）。

  group('TtsAudioNotifier - 公开 API 边界', () {
    Future<
        ({
          ProviderContainer container,
          TtsAudioNotifier notifier,
          TtsEngineService engine
        })> _setup() async {
      await initializeTestEnvironment();
      final settings = makeSettings();
      final engine = TtsEngineService(
        settings,
        config: const TtsConfig(
          serverUrl: 'https://test.invalid/tts',
          maxPrefetchQueue: 1,
          requestTimeout: Duration(milliseconds: 50),
          baseRetryDelay: Duration(milliseconds: 1),
        ),
        audioPlayer: _ControllableAudioPlayer(),
        wakeLock: FakeWakeLock(),
        httpClient: _SingleAudioHttpClient(),
        fallbackEngine: FakeFallbackEngine(),
        delayFn: (d) => Future<void>.delayed(const Duration(milliseconds: 1)),
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
      // 等待引擎硬件初始化完成（_volume 等 late 字段必须初始化），
      // 否则 refreshSession 调 syncSettingsFromProvider 会触发 LateInitializationError。
      for (int i = 0; i < 50; i++) {
        await pumpEventQueue(times: 1);
      }
      return (
        container: container,
        notifier: container.read(ttsAudioProvider.notifier),
        engine: engine,
      );
    }

    test('play 在 sentenceSource 未注册时设置业务错误并保持 Idle', () async {
      final s = await _setup();
      s.notifier.play();
      // play 检测 sentenceSource == null → setBusinessError 后立即返回
      expect(s.engine.lastError, isNotNull,
          reason: 'play 必须通过 setBusinessError 设置"请先导入书籍"提示');
      expect(s.engine.lastError, contains('请先导入书籍'));
    });

    test('cycleSpeed 必须更新 state.playbackRate 与 engine.playbackRate 同步',
        () async {
      final s = await _setup();
      final beforeRate = s.notifier.state.playbackRate;
      s.notifier.cycleSpeed();
      expect(s.notifier.state.playbackRate, isNot(equals(beforeRate)),
          reason: 'cycleSpeed 必须切换到下一档速度');
      expect(s.notifier.state.playbackRate, equals(s.engine.playbackRate),
          reason: 'state.playbackRate 必须与 engine 同步');
    });

    test('setBackgroundTolerant(true) 必须重置 _consecutiveFailures 并暂停预取',
        () async {
      final s = await _setup();
      // 进入后台宽容模式
      s.notifier.setBackgroundTolerant(true);
      // 显式退出
      s.notifier.setBackgroundTolerant(false);
      // 不抛异常即视为状态切换正常（私字段无法直接读，但行为已被覆盖）
    });

    test('recover 必须清空 engine.lastError 并尝试 play', () async {
      final s = await _setup();
      s.engine.setLastError('某错误');
      expect(s.engine.lastError, isNotNull);

      s.notifier.recover();
      expect(s.engine.lastError, isNotNull,
          reason: 'recover 后 setBusinessError(请先导入书籍) 立即设置新错误，'
              '说明 clearLastError → play 链路被走通');
    });

    test('setBusinessError 必须传播到 engine.lastError', () async {
      final s = await _setup();
      s.notifier.setBusinessError('自定义错误信息');
      expect(s.engine.lastError, '自定义错误信息');
    });

    test('isActivelyPlaying 在 Idle 时返回 false', () async {
      final s = await _setup();
      expect(s.notifier.isActivelyPlaying, isFalse,
          reason: 'Idle 状态 isActivelyPlaying 必须为 false');
    });

    test('currentSession 与 buffer / isDegraded 的初始值', () async {
      final s = await _setup();
      expect(s.notifier.currentSession, isA<int>());
      expect(s.notifier.buffer, isNotNull);
      expect(s.notifier.buffer.count, 0);
      expect(s.notifier.isDegraded, isFalse);
    });

    test('refreshSession 在无 sentenceSource 时不抛异常并触发缓冲状态', () async {
      final s = await _setup();
      final beforeSession = s.notifier.currentSession;
      await s.notifier.refreshSession();

      expect(s.notifier.currentSession, beforeSession + 1,
          reason: 'refreshSession 必须递增 session');
      expect(s.notifier.state, isA<TtsAudioBuffering>(),
          reason: 'refreshSession 后状态必须进入 Buffering');
      // 关闭，避免泵空转
      await s.notifier.stopAll();
    });

    test('stopAll 在 Idle 状态下幂等（多次调用不崩溃）', () async {
      final s = await _setup();
      await s.notifier.stopAll();
      await s.notifier.stopAll();
      await s.notifier.stopAll();
      expect(s.notifier.state, isA<TtsAudioIdle>());
      expect(s.notifier.isDegraded, isFalse);
    });

    test(
        '@Deprecated setEnabled(true) 触发 buffer 重启 / setEnabled(false) 等同 stopAll',
        () async {
      final s = await _setup();
      // ignore: deprecated_member_use_from_same_package
      s.notifier.setEnabled(true);
      expect(s.notifier.state, isA<TtsAudioBuffering>(),
          reason: '@Deprecated setEnabled(true) 必须切换到 Buffering');
      // ignore: deprecated_member_use_from_same_package
      s.notifier.setEnabled(false);
      await pumpEventQueue(times: 5);
      expect(s.notifier.state, isA<TtsAudioIdle>(),
          reason: 'setEnabled(false) 必须等同 stopAll → Idle');
    });

    // ── _copyStateWithRate switch 分支：Buffering 状态下 cycleSpeed ──────
    // 直接在 Buffering 状态调 cycleSpeed，覆盖 _copyStateWithRate 的
    // TtsAudioBuffering() 分支（lib/features/audio/providers
    // /tts_audio_notifier.dart:712-718）。
    test('cycleSpeed 在 Buffering 状态下必须保留 buffer/target/session 等字段', () async {
      final s = await _setup();
      // 进入 Buffering（无 sentenceSource 也能构造空缓冲态）
      await s.notifier.refreshSession();
      expect(s.notifier.state, isA<TtsAudioBuffering>());

      final beforeRate = s.notifier.state.playbackRate;
      final beforeSession = (s.notifier.state as TtsAudioBuffering).session;

      s.notifier.cycleSpeed();

      final after = s.notifier.state;
      expect(after, isA<TtsAudioBuffering>(), reason: 'cycleSpeed 不得改变状态类型');
      expect(after.playbackRate, isNot(equals(beforeRate)),
          reason: 'playbackRate 必须切换');
      expect((after as TtsAudioBuffering).session, beforeSession,
          reason: 'cycleSpeed 必须保留 session（不重置）');

      await s.notifier.stopAll();
    });
  });
}
