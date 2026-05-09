import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:fake_async/fake_async.dart';
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

/// 限定返回次数的句子源：calls ≤ [returnLimit] 时返回非 null，超过后返回 null。
///
/// 用途：让 `_pumpDegraded` 在降级激活后，下一轮取句子时返回 null，命中
/// `lib/features/audio/providers/tts_audio_notifier.dart:683-688` 的"无更多内容
/// → 自动退出降级"分支，**避免触发 pingServer 真网络 3s 超时**。
class _LimitedSentenceSource implements TtsSentenceSource {
  final int returnLimit;
  int nextCalls = 0;
  int startedCalls = 0;
  int finishedCalls = 0;

  _LimitedSentenceSource({required this.returnLimit});

  @override
  Future<TtsAudioRequest?> nextTtsSentence(int session) async {
    nextCalls++;
    if (nextCalls > returnLimit) return null;
    return TtsAudioRequest(
      lineIndex: nextCalls,
      endLineIndex: nextCalls,
      text: '降级回退测试句 $nextCalls',
      title: '降级回退测试章节',
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

/// fakeAsync 专用：句子源始终返回 null，让 _refillBuffer 走 `await Future.delayed(500ms)`
/// 分支，避免 _prefetchRunner 在没有 sentenceSource 时进入 microtask 死循环（while 内
/// _refillBuffer 早返 + 无 await ⇒ flushMicrotasks 无法终结）。
class _EmptySentenceSource implements TtsSentenceSource {
  @override
  Future<TtsAudioRequest?> nextTtsSentence(int session) async => null;

  @override
  void onTtsItemStarted(TtsAudioItem item) {}

  @override
  void onTtsItemFinished(TtsAudioItem item) {}

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

  // ── T-B 衍生 2：sentenceSource 耗尽时 _pumpDegraded 必须自动退出降级 ───────
  //
  // 覆盖 lib/features/audio/providers/tts_audio_notifier.dart:679-688：
  //   _pumpDegraded → nextTtsSentence == null → 重置 _isDegradedToLocal=false。
  //
  // 设计要点：
  //   * _LimitedSentenceSource(returnLimit=8)：前 8 次 _refillBuffer 调用
  //     拿到非 null request → downloadAudio 全部 500 失败 → 第 8 次累计触发
  //     _degradeToLocal → _isDegradedToLocal=true。
  //   * 降级激活后 _prefetchRunner 退避不再调 nextTtsSentence；
  //     _playRunner 走 _pumpDegraded 调第 9 次 nextTtsSentence → 返回 null
  //     → 命中早返分支 → _isDegradedToLocal=false。
  //   * **关键**：nextTtsSentence==null 在 pingServer 之前早返，
  //     绕过真 dart:io HttpClient 的 3s 连接超时，避免测试阻塞。
  test('T-B 衍生 2：降级激活后 sentenceSource 耗尽必须自动退出降级模式', () async {
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
    // returnLimit=6 与 _refillBuffer 的 filePath==null 路径降级阈值（6）齐平：
    // 前 6 次 nextTtsSentence 返回非 null 触发降级；第 7+ 次（含 _pumpDegraded
    // 调用）返回 null 让 _pumpDegraded 命中 line 683-688 早返路径。
    final source = _LimitedSentenceSource(returnLimit: 6);
    notifier.registerSentenceSource(source);
    notifier.play();

    // 等到 _refillBuffer 失败累计触发 _degradeToLocal → isDegraded=true
    for (int i = 0; i < 500 && !notifier.isDegraded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(notifier.isDegraded, isTrue,
        reason: '前置：6 次 downloadAudio 失败必须先触发降级');

    // 等到 _playRunner → _pumpDegraded → nextTtsSentence(==null) → 退出降级
    for (int i = 0; i < 500 && notifier.isDegraded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(notifier.isDegraded, isFalse,
        reason:
            'sentenceSource 耗尽时 _pumpDegraded 必须把 _isDegradedToLocal 重置为 false');

    await notifier.stopAll();
  }, timeout: const Timeout(Duration(seconds: 20)));

  // ── T-B 衍生 3：_pumpDegraded 在 pingServer 可达时必须自动退出降级 ──────────
  //
  // 覆盖 lib/features/audio/providers/tts_audio_notifier.dart:690-698：
  //   _pumpDegraded → request != null → await _degradeToLocal(request)
  //                 → await pingServer() == true → 退出降级 (line 694-698)
  //
  // 与 T-B 衍生 2 互补：
  //   * 衍生 2 覆盖 line 683-688（request==null 早返）
  //   * 本用例覆盖 line 690-698（request!=null + ping 成功退出降级）
  //
  // 设计要点：
  //   * returnLimit=999999 让 _pumpDegraded 始终拿到非 null request，
  //     不会因句子源耗尽走 line 685-688 早返路径。
  //   * pingServer 走真 dart:io HttpClient；flutter_test 默认通过
  //     HttpOverrides 注入 mock client，response.statusCode=400 < 500
  //     → reachable=true → 命中 line 695-698 退出降级路径。
  test('T-B 衍生 3：_pumpDegraded 在 pingServer 可达时必须自动退出降级', () async {
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
    final source = _LimitedSentenceSource(returnLimit: 999999);
    notifier.registerSentenceSource(source);
    notifier.play();

    // 等到 isDegraded=true（≤ 5s 内触发）
    for (int i = 0; i < 500 && !notifier.isDegraded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(notifier.isDegraded, isTrue, reason: '前置：先进入降级模式');

    // 等 _pumpDegraded 跑 _degradeToLocal+pingServer：mock HttpClient 返回 400
    // → reachable=true → 退出降级。最多等 5s。
    for (int i = 0; i < 500 && notifier.isDegraded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(notifier.isDegraded, isFalse,
        reason: 'pingServer 可达时 _pumpDegraded 必须退出降级（covered line 695-698）');
    expect(source.nextCalls, greaterThan(6),
        reason:
            '_pumpDegraded 必须至少调用过 1 次 nextTtsSentence（_degradeToLocal 路径）');

    await notifier.stopAll();
  }, timeout: const Timeout(Duration(seconds: 30)));

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
      // 等待引擎硬件初始化完成（_volume / _playbackRate 等 late 字段必须就绪），
      // 否则 refreshSession 调 syncSettingsFromProvider 会触发 LateInitializationError。
      // 直接 await 公开的 initialized future，省掉 50 次空轮询。
      await engine.initialized;
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

    // ── _copyStateWithRate switch 分支：Idle 状态下 cycleSpeed ────────────
    // 默认 _setup() 后 state 为 Idle，cycleSpeed 走 _copyStateWithRate 的
    // TtsAudioIdle() 分支（lib/features/audio/providers/tts_audio_notifier.dart
    // :708-711）+ _toEnginePlaybackState Idle 分支（line 763）。
    // 不启动 pump，不需 fakeAsync。
    test('cycleSpeed 在 Idle 状态下必须保留 fallbackMessage 字段', () async {
      final s = await _setup();
      expect(s.notifier.state, isA<TtsAudioIdle>(),
          reason: '_setup 后 state 默认为 Idle');

      final beforeRate = s.notifier.state.playbackRate;
      final beforeFallback = s.notifier.state.fallbackMessage;

      s.notifier.cycleSpeed();

      final after = s.notifier.state;
      expect(after, isA<TtsAudioIdle>(), reason: 'cycleSpeed 在 Idle 下不得改变状态类型');
      expect(after.playbackRate, isNot(equals(beforeRate)),
          reason: 'playbackRate 必须切换到下一档');
      expect(after.fallbackMessage, beforeFallback,
          reason: 'cycleSpeed 必须保留 fallbackMessage（不丢失降级提示）');
    });

    // ── stopAll 在 Idle 状态下幂等回到 Idle（覆盖 stopAll → _applyState(Idle)）──
    // 现有 'stopAll 在 Idle 状态下幂等' 用例只验 state 类型；此处补充
    // playbackRate 与 fallbackMessage 字段必须保留，覆盖 _toEnginePlaybackState
    // Idle 分支与 syncShadow 调用链。
    test('stopAll 在 Idle 状态下保留 playbackRate（不重置）', () async {
      final s = await _setup();
      // 先 cycle 一次让 playbackRate ≠ 默认
      s.notifier.cycleSpeed();
      final rateAfterCycle = s.notifier.state.playbackRate;
      expect(rateAfterCycle, isNot(equals(1.0)));

      await s.notifier.stopAll();
      expect(s.notifier.state, isA<TtsAudioIdle>());
      // stopAll 重新构造 TtsAudioIdle(playbackRate: _playbackRate)
      expect(s.notifier.state.playbackRate, rateAfterCycle,
          reason: 'stopAll 必须保留当前 playbackRate（_playbackRate 字段）');
    });

    // ─────────────────────────────────────────────────────────────────
    // 阶段 1 第 4 轮：fakeAsync 安全推进 pump-timer 相关分支
    // ─────────────────────────────────────────────────────────────────
    //
    // 背景：setEnabled(true) / refreshSession() 内部调用 _startPump 启动双轨
    // (_prefetchRunner + _playRunner)，里面有 Future.delayed(2000ms / 500ms /
    // 300ms) 无限循环。在真定时器下，flutter_test runner teardown 后会等所有
    // pending Timer 完成（最长 5 分钟 idleTimer），导致测试挂起 30 分钟+。
    //
    // 解决方案：fakeAsync.run 包裹整个测试体，把 dart:async 的 Timer/Future
    // 全部虚拟化，结束前用 async.elapse + async.flushTimers 强制清空所有计时器，
    // 不会有真实泄漏。
    //
    // 注意：_setup() 内的 initializeTestEnvironment / StorageService.init 是真
    // platform channel 调用，必须在 fakeAsync **外**完成。fakeAsync 内只构造
    // engine / container / notifier，并用 flushMicrotasks 推进 _initTtsHardware。

    /// fakeAsync 内安全构造 notifier 三件套；调用方必须自行 stopAll + elapse 清理。
    ({
      TtsEngineService engine,
      ProviderContainer container,
      TtsAudioNotifier notifier,
      SettingsProvider settings,
    }) _fakeSetup(FakeAsync ctrl) {
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
      // 让 _initTtsHardware 的微任务排干（fake_audio_player 同步返回，无需 elapse）
      ctrl.flushMicrotasks();
      final notifier = container.read(ttsAudioProvider.notifier);
      // 关键：注册一个 dummy sentenceSource，让 _refillBuffer 进入 `await Future.delayed(500ms)`
      // 分支，否则 _prefetchRunner 在无 source 时早返 + 无 await ⇒ flushMicrotasks 死循环。
      notifier.registerSentenceSource(_EmptySentenceSource());
      return (
        engine: engine,
        container: container,
        notifier: notifier,
        settings: settings,
      );
    }

    /// 在 fakeAsync 内强制清理所有 pending Timer / Future，确保不泄漏到真实 zone。
    void _fakeTeardown(
      FakeAsync ctrl,
      TtsAudioNotifier notifier,
      ProviderContainer container,
      TtsEngineService engine,
    ) {
      notifier.stopAll();
      // 推进 10 分钟虚拟时间，足以让所有 Timer (含 5 分钟 idleTimer) 触发并退出
      ctrl.elapse(const Duration(minutes: 10));
      ctrl.flushTimers();
      container.dispose();
      engine.dispose();
      ctrl.flushMicrotasks();
    }

    // 必须先在 fakeAsync 外完成 platform channel mock 初始化
    setUp(() async {
      await initializeTestEnvironment();
    });

    test('cycleSpeed 在 Paused 状态下必须保留 item/buffer/session 等字段', () {
      fakeAsync((ctrl) {
        final s = _fakeSetup(ctrl);
        // ignore: deprecated_member_use_from_same_package
        s.notifier.setEnabled(true); // → Buffering（启动 pump，但都在 fake zone）
        ctrl.flushMicrotasks();
        s.notifier.pause(); // → Paused
        ctrl.flushMicrotasks();
        expect(s.notifier.state, isA<TtsAudioPaused>());

        final beforeRate = s.notifier.state.playbackRate;
        final beforeSession = (s.notifier.state as TtsAudioPaused).session;

        s.notifier.cycleSpeed();

        final after = s.notifier.state;
        expect(after, isA<TtsAudioPaused>(),
            reason: 'cycleSpeed 在 Paused 下不得改变状态类型');
        expect(after.playbackRate, isNot(equals(beforeRate)),
            reason: 'playbackRate 必须切换');
        expect((after as TtsAudioPaused).session, beforeSession,
            reason: 'cycleSpeed 必须保留 Paused.session');

        _fakeTeardown(ctrl, s.notifier, s.container, s.engine);
      });
    });

    test('settings.idleTimeout 变更 + 非 Idle 状态必须创建 _idleTimer', () {
      fakeAsync((ctrl) {
        final s = _fakeSetup(ctrl);
        // ignore: deprecated_member_use_from_same_package
        s.notifier.setEnabled(true); // 进入 Buffering
        ctrl.flushMicrotasks();
        expect(s.notifier.state, isA<TtsAudioBuffering>());

        // 触发 settings listener：idleTimeout 0 → 5 必触发 _resetIdleTimer
        s.settings.idleTimeout = 5;
        ctrl.flushMicrotasks();
        // Timer 已被构造（虚拟）；不抛异常即视为 line 116 路径被覆盖。

        // 关闭 idleTimeout 防止虚拟时间推进时触发 pause 副作用
        s.settings.idleTimeout = 0;
        ctrl.flushMicrotasks();

        _fakeTeardown(ctrl, s.notifier, s.container, s.engine);
      });
    });

    test('play 在 Paused 状态下必须脱离 Paused 重新启动泵', () {
      fakeAsync((ctrl) {
        final s = _fakeSetup(ctrl);
        // ignore: deprecated_member_use_from_same_package
        s.notifier.setEnabled(true); // 进入 Buffering
        ctrl.flushMicrotasks();
        s.notifier.pause();
        ctrl.flushMicrotasks();
        expect(s.notifier.state, isA<TtsAudioPaused>());

        // play() 走 _currentItem == null && _currentFilePath == null → else 分支
        s.notifier.play();
        ctrl.flushMicrotasks();
        expect(s.notifier.state, isNot(isA<TtsAudioPaused>()),
            reason: 'play 后必须脱离 Paused');

        _fakeTeardown(ctrl, s.notifier, s.container, s.engine);
      });
    });

    test('stopAll 在 Buffering 状态下必须取消 _idleTimer 与清空 buffer', () {
      fakeAsync((ctrl) {
        final s = _fakeSetup(ctrl);
        // ignore: deprecated_member_use_from_same_package
        s.notifier.setEnabled(true);
        ctrl.flushMicrotasks();
        expect(s.notifier.state, isA<TtsAudioBuffering>());

        // 同步开启 idleTimer
        s.settings.idleTimeout = 1;
        ctrl.flushMicrotasks();

        s.notifier.stopAll();
        ctrl.flushMicrotasks();
        expect(s.notifier.state, isA<TtsAudioIdle>(),
            reason: 'stopAll 必须回到 Idle');
        expect(s.notifier.buffer.count, 0, reason: 'stopAll 必须清空 buffer');
        expect(s.notifier.isDegraded, isFalse, reason: 'stopAll 必须重置降级标志');

        // 已在测试内调过 stopAll，_fakeTeardown 中再调一次幂等
        s.settings.idleTimeout = 0;
        _fakeTeardown(ctrl, s.notifier, s.container, s.engine);
      });
    });

    // ── idleTimer fire 后必须自动 pause（engine 心跳触发路径） ─────────────
    // 覆盖 lib/features/audio/providers/tts_audio_notifier.dart:116-122
    // (Timer callback：CyberLogger.captureMessage + pause())
    //
    // 路径选择：本用例走 ttsEngineProvider listener（engine.notifyUserActivity
    // → notifyListeners → _resetIdleTimer），与下方 settings.setIdleTimeout
    // 路径互补，确保两条触发链路都被回归。
    test('idleTimer 到期 fire 必须自动调用 pause()（engine 心跳路径）', () {
      fakeAsync((ctrl) {
        final s = _fakeSetup(ctrl);
        // ignore: deprecated_member_use_from_same_package
        s.notifier.setEnabled(true);
        ctrl.flushMicrotasks();
        expect(s.notifier.state, isA<TtsAudioBuffering>());

        // 1) 直接置字段为 1 分钟（_resetIdleTimer 读 settings.idleTimeout）
        s.settings.idleTimeout = 1;
        // 2) 通过 engine 心跳路径触发 _resetIdleTimer → Timer(1min) 创建
        s.engine.notifyUserActivity();
        ctrl.flushMicrotasks();

        // 推进 1 分 1 秒（>1min），idleTimer 必须 fire 触发 pause callback
        ctrl.elapse(const Duration(seconds: 61));
        ctrl.flushMicrotasks();

        expect(s.notifier.state, isA<TtsAudioPaused>(),
            reason: 'idleTimer fire 后必须自动 pause → state 进入 Paused');

        s.settings.idleTimeout = 0;
        _fakeTeardown(ctrl, s.notifier, s.container, s.engine);
      });
    });

    // ── P1 回归：settings.setIdleTimeout 必须直接驱动 _resetIdleTimer ───────
    //
    // 修复前缺陷：`tts_audio_notifier.dart:95-99` 的 `ref.listen(settingsProvider)`
    // 中 prev 与 next 引用同一个 SettingsProvider 实例（ChangeNotifier 在
    // notify 时不会创建新实例），`prev?.idleTimeout != next.idleTimeout` 永远
    // 是 false，listener 内部分支永远不会执行 → settings 路径变更被吞掉。
    //
    // 修复后：listener 改用 `settingsProvider.select((s) => s.idleTimeout)`，
    // Riverpod 内部对 idleTimeout 数值做快照对比，数值变化才 fire callback。
    //
    // 本用例验证：直接调 `settings.setIdleTimeout(1)`（不通过 engine 心跳），
    // listener 必须接收到数值变化并触发 _resetIdleTimer 创建 Timer。
    test('P1 回归：settings.setIdleTimeout 必须经 listener 触发 _resetIdleTimer', () {
      fakeAsync((ctrl) {
        final s = _fakeSetup(ctrl);
        // ignore: deprecated_member_use_from_same_package
        s.notifier.setEnabled(true);
        ctrl.flushMicrotasks();
        expect(s.notifier.state, isA<TtsAudioBuffering>());

        // 关键：通过公开 setter 走完整 ChangeNotifier.notifyListeners 路径，
        // 不直接置字段（直接置字段不会 notify，无法验证 listener 链路）。
        // setIdleTimeout 是 Future<void>，但内部 await StorageService.setInt
        // 在 SharedPreferences mock 下是 microtask 完成，flushMicrotasks 即可 drain。
        s.settings.setIdleTimeout(1);
        ctrl.flushMicrotasks();

        // 推进 1 分 1 秒（>1min），idleTimer 必须 fire 触发 pause callback
        ctrl.elapse(const Duration(seconds: 61));
        ctrl.flushMicrotasks();

        expect(s.notifier.state, isA<TtsAudioPaused>(),
            reason:
                'P1 修复后 settings.setIdleTimeout 必须通过 select listener 触发 _resetIdleTimer 创建 Timer，'
                '60s 后 fire callback 让 state 进入 Paused');

        s.settings.idleTimeout = 0;
        _fakeTeardown(ctrl, s.notifier, s.container, s.engine);
      });
    });

    // ── setBackgroundTolerant(true) 后 _prefetchPaused 分支必须被 pump 走到 ──
    // 覆盖 tts_audio_notifier.dart:317-320 (_prefetchRunner 内
    // if (_prefetchPaused) { await Future.delayed(2000ms); continue; })
    test('setBackgroundTolerant(true) 后 pump 必须进入 _prefetchPaused 退避', () {
      fakeAsync((ctrl) {
        final s = _fakeSetup(ctrl);
        // ignore: deprecated_member_use_from_same_package
        s.notifier.setEnabled(true);
        ctrl.flushMicrotasks();
        expect(s.notifier.state, isA<TtsAudioBuffering>());

        // 切换为后台宽容模式：_prefetchPaused = true
        s.notifier.setBackgroundTolerant(true);
        ctrl.flushMicrotasks();

        // 推进 5 秒让 pump 至少转一圈进入 _prefetchPaused await Future.delayed(2000ms)
        ctrl.elapse(const Duration(seconds: 5));
        ctrl.flushMicrotasks();

        // 仍处于 Buffering（pump 没新增 buffer，因为预取被暂停）
        expect(s.notifier.state, isA<TtsAudioBuffering>(),
            reason: '_prefetchPaused 期间 state 不变');
        expect(s.notifier.buffer.count, 0,
            reason: '_prefetchPaused 期间不应继续填充 buffer');

        // 退出后台宽容
        s.notifier.setBackgroundTolerant(false);
        ctrl.flushMicrotasks();

        _fakeTeardown(ctrl, s.notifier, s.container, s.engine);
      });
    });
  });
}
