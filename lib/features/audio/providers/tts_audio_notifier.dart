import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yueyou/core/utils/cyber_logger.dart';
import 'package:yueyou/features/audio/domain/tts_audio_buffer.dart';
import 'package:yueyou/features/audio/domain/tts_audio_state.dart';
import 'package:yueyou/features/audio/domain/tts_audio_state_helpers.dart';
import 'package:yueyou/features/audio/providers/tts_fallback_controller.dart';
import 'package:yueyou/features/audio/providers/tts_paused_interrupt_guard.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';

/// TTS 音频流状态机 Provider。
final ttsAudioProvider =
    NotifierProvider<TtsAudioNotifier, TtsAudioState>(TtsAudioNotifier.new);

/// TTS 音频流状态机编排层。
///
/// ## 架构
///
/// 双轨并行生产者/消费者模型：
/// - **预加载轨道**：`_prefetchRunner` 后台持续下载音频文件，填充 `TtsAudioBuffer`
/// - **播放轨道**：`_playRunner` 串行消费缓冲队列，播完即焚
/// - 两轨道通过共享 `TtsAudioBuffer` 通信，互不阻塞
///
/// ## 状态流转
///
/// Idle ──play()──▶ Buffering ──缓冲就绪──▶ Playing ──pause()──▶ Paused
///                   ▲                       │                    │
///                   │      缓冲耗尽           │    resumeAudio()  │
///                   └───────────────────────┘ ◀──────────────────┘
///                                            Error ──recover()──▶ Buffering
class TtsAudioNotifier extends Notifier<TtsAudioState> {
  late final TtsEngineService _engine;
  late final TtsAudioBuffer _buffer;
  TtsSentenceSource? _sentenceSource;
  TtsAudioItem? _currentItem;
  String? _currentFilePath; // 当前播放文件路径，用于暂停后恢复
  int _session = 0;
  double _playbackRate = 1.0;
  String? _fallbackMessage;
  bool _disposed = false;
  bool _pumpActive = false;
  int _consecutiveFailures = 0;
  bool _isPausing = false;
  bool _backgroundTolerant = false;
  bool _prefetchPaused = false;
  Timer? _idleTimer; // 静默暂停计时器

  // PR-D 抽出的子系统：暂停中断守卫 + 本地降级控制器。
  final TtsPausedInterruptGuard _pausedGuard = TtsPausedInterruptGuard();
  late final TtsFallbackController _fallback;

  /// 设置后台宽容模式：提高降级阈值，避免后台限网触发误降级。
  void setBackgroundTolerant(bool value) {
    _backgroundTolerant = value;
    if (value) {
      _prefetchPaused = true;
      _consecutiveFailures = 0;
    } else {
      _prefetchPaused = false;
      _consecutiveFailures = 0;
    }
  }

  /// 注册句子源（由 ReaderProvider 在构造时调用）。
  void registerSentenceSource(TtsSentenceSource source) {
    _sentenceSource = source;
  }

  /// TTS 是否处于活跃状态（播放或缓冲）。
  /// 供外部（如 ReaderProvider）在调用 refreshSession 前做守卫判断。
  /// 使用 Riverpod state（纯 Dart，每次 build 干净初始化），
  /// 比 native audioplayers 状态更可靠。
  bool get isActivelyPlaying {
    final s = state;
    return s is TtsAudioPlaying || s is TtsAudioBuffering;
  }

  @override
  TtsAudioState build() {
    _engine = ref.read(ttsEngineProvider);
    _buffer = TtsAudioBuffer(maxSize: _engine.maxBufferedCount);
    _playbackRate = _engine.playbackRate;
    _fallback = TtsFallbackController(
      engine: _engine,
      pausedGuard: _pausedGuard,
      sentenceSourceGetter: () => _sentenceSource,
      sessionGetter: () => _session,
      playbackRateGetter: () => _playbackRate,
      bufferGetter: () => _buffer,
      currentItemGetter: () => _currentItem,
      currentItemSetter: (item) => _currentItem = item,
      isDisposed: () => _disposed,
      applyState: _applyState,
      snapshotOf: snapshotOf,
      onConsecutiveFailuresReset: (n) => _consecutiveFailures = n,
      fallbackMessageSetter: (msg) => _fallbackMessage = msg,
    );

    ref.onDispose(() {
      _disposed = true;
      _pumpActive = false;
      _idleTimer?.cancel();
      _buffer.clear();
    });

    // 核心：监听引擎的心跳信号（notifyUserActivity 触发的 notifyListeners）
    ref.listen(ttsEngineProvider, (prev, next) {
      _resetIdleTimer();
    });

    // 核心：监听设置中的时长变更
    //
    // 修复 P1（dead code）：`settingsProvider` 是 ChangeNotifierProvider，
    // 在 notify 时 prev 与 next 引用同一个 SettingsProvider 实例，
    // 直接比较 `prev?.idleTimeout != next.idleTimeout` 永远 false，分支不会触发。
    // 改用 `select` 让 Riverpod 内部对 idleTimeout 数值做快照对比，
    // 只在数值真正变化时 fire callback。
    ref.listen<int>(
      settingsProvider.select((s) => s.idleTimeout),
      (prev, next) {
        if (prev != next) _resetIdleTimer();
      },
    );

    return TtsAudioIdle(playbackRate: _playbackRate, fallbackMessage: null);
  }

  /// 内部重置空闲计时器（静默暂停）。
  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;

    final settings = ref.read(settingsProvider);
    final minutes = settings.idleTimeout;

    // 如果设置为 0 (永不) 或者当前未在播放/缓冲，则不启动计时
    if (minutes <= 0) return;
    if (state is TtsAudioIdle) return;

    _idleTimer = Timer(Duration(minutes: minutes), () {
      CyberLogger.captureMessage(
        '[TTS] 静默暂停：用户已空闲 ${minutes}m，自动停播',
        tag: 'tts',
      );
      pause();
    });
  }

  // ─── 公开 API ──────────────────────────────────────────────

  /// 启动或恢复播放。
  void play() {
    if (_disposed) return;
    _engine.clearLastError();
    if (_sentenceSource == null) {
      setBusinessError('无法开启 TTS：请先导入书籍');
      return;
    }
    _consecutiveFailures = 0;
    _resetIdleTimer(); // 启动播放时激活计时器

    if (_currentFilePath != null) {
      // 恢复暂停：重播当前文件（pause 时用 stop 释放了播放器，无法 resume）
      // 无论缓冲区是否有内容，都先把当前句插入队首，避免跳句
      _buffer.prepend(
        BufferedAudio(
          filePath: _currentFilePath!,
          lineIndex: _currentItem?.lineIndex ?? -1,
          endLineIndex: _currentItem?.endLineIndex ?? -1,
          text: _currentItem?.text ?? '',
          title: _currentItem?.title ?? '',
          session: _session,
        ),
      );
      _startPump();
      _applyState(
        TtsAudioPlaying(
          item: snapshotOf(_currentItem!),
          bufferedCount: _buffer.count,
          targetCount: _buffer.maxSize,
          playbackRate: _playbackRate,
          fallbackMessage: _fallbackMessage,
        ),
      );
    } else if (_currentItem != null) {
      // 没有文件路径但有 currentItem（可能是正在下载时暂停）
      _startPump();
    } else {
      _session++;
      _applyState(
        TtsAudioBuffering(
          bufferedCount: _buffer.count,
          targetCount: _buffer.maxSize,
          progress: _buffer.healthRatio,
          session: _session,
          playbackRate: _playbackRate,
          fallbackMessage: _fallbackMessage,
        ),
      );
      _startPump();
    }
  }

  /// 暂停播放。
  Future<void> pause() async {
    _pumpActive = false;
    _pausedGuard.mark(_currentItem);
    _isPausing = true; // 开启暂停标识，阻止 _onPlaybackComplete 推进进度
    try {
      await _engine.stopAudio();
      await _engine.pauseAudio();
    } finally {
      _isPausing = false;
    }

    _applyState(
      TtsAudioPaused(
        item: _currentItem != null ? snapshotOf(_currentItem!) : null,
        bufferedCount: _buffer.count,
        targetCount: _buffer.maxSize,
        session: _session,
        playbackRate: _playbackRate,
        fallbackMessage: _fallbackMessage,
      ),
    );
  }

  /// 停止全部播放任务。
  Future<void> stopAll() async {
    _session++;
    _pumpActive = false; // 终止双轨泵，避免删书后 _prefetchRunner 持续空查询占 CPU 与 2048 游戏争用帧
    _idleTimer?.cancel();
    await _engine.stopAll();
    _buffer.clear();
    _currentItem = null;
    _currentFilePath = null;
    _fallback.isDegradedToLocal = false;
    _consecutiveFailures = 0;
    _pausedGuard.clear();
    _applyState(
      TtsAudioIdle(playbackRate: _playbackRate, fallbackMessage: null),
    );
  }

  /// 切换播放倍速。
  void cycleSpeed() {
    _engine.cycleSpeed();
    _playbackRate = _engine.playbackRate;
    state = copyStateWithRate(state, _playbackRate);
  }

  /// 清除错误并尝试恢复会话。
  void recover() {
    _engine.clearLastError();
    play();
  }

  /// 设置脱敏后的业务错误提示。
  void setBusinessError(String message) {
    _engine.setLastError(message);
  }

  /// 刷新会话（切章/换声时由外部调用，立即生效）。
  Future<void> refreshSession() async {
    // 0. 强制同步当前设置（音色等），确保引擎用最新参数下载
    _engine.syncSettingsFromProvider(ref.read(settingsProvider));

    // 1. 同步清理：立即递增会话并清空缓冲，防止旧循环继续工作
    _session++;
    _buffer.clear();
    _currentItem = null;
    _currentFilePath = null;
    _fallback.isDegradedToLocal = false;
    _consecutiveFailures = 0;
    _fallbackMessage = null;
    _pausedGuard.clear();

    // 2. 重置句子源游标：确保从当前 currentIndex 重新开始预取
    _sentenceSource?.resetFetchIndex();

    // 3. 停播引擎：释放 playFile 的 await 阻塞
    // 此处必须在 _session++ 之后，这样旧的 _onPlaybackComplete 会因 session 不匹配而直接 return
    await _engine.stopAudio();
    await _engine.pauseAudio();

    // 4. 立即进入缓冲并启动泵
    _applyState(
      TtsAudioBuffering(
        bufferedCount: 0,
        targetCount: _buffer.maxSize,
        progress: 0.0,
        session: _session,
        playbackRate: _playbackRate,
        fallbackMessage: null,
      ),
    );
    _startPump();
  }

  @Deprecated('仅用于测试兼容，请使用 refreshSession/stopAll')
  void setEnabled(bool enabled) {
    if (enabled) {
      _consecutiveFailures = 0;
      _session++;
      _fallback.isDegradedToLocal = false;
      _applyState(
        TtsAudioBuffering(
          bufferedCount: 0,
          targetCount: _buffer.maxSize,
          progress: 0.0,
          session: _session,
          playbackRate: _playbackRate,
          fallbackMessage: null,
        ),
      );
      _startPump();
    } else {
      stopAll();
    }
  }

  // ─── 双轨编排泵 ────────────────────────────────────────────
  //
  // 预加载轨道与播放轨道独立运行，通过 _pumpActive 协同生命周期。

  void _startPump() {
    if (_pumpActive || _disposed) return;
    _pumpActive = true;
    _prefetchRunner();
    _playRunner();
  }

  /// 预加载轨道：后台持续填充缓冲队列，与播放互不阻塞。
  Future<void> _prefetchRunner() async {
    try {
      while (_pumpActive && !_disposed) {
        if (_fallback.isDegradedToLocal) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          continue;
        }
        if (_prefetchPaused) {
          await Future<void>.delayed(const Duration(milliseconds: 2000));
          continue;
        }
        if (_buffer.needsRefill) {
          await _refillBuffer();
        } else {
          final delayMs = _buffer.isFull
              ? 2000
              : _buffer.healthRatio >= 0.6
                  ? 1000
                  : 500;
          await Future<void>.delayed(Duration(milliseconds: delayMs));
        }
      }
    } catch (e, st) {
      // coverage:ignore-start
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'tts',
        extra: {'context': 'TTS 预加载轨道异常'},
      );
      // coverage:ignore-end
    }
  }

  /// 播放轨道：串行消费缓冲队列，播完即进入下一句，不回落 Buffering。
  Future<void> _playRunner() async {
    try {
      while (_pumpActive && !_disposed) {
        if (_fallback.isDegradedToLocal) {
          await _fallback.pumpDegraded();
          continue;
        }
        if (!_buffer.isEmpty) {
          await _playNext();
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
    } catch (e, st) {
      // coverage:ignore-start
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'tts',
        extra: {'context': 'TTS 播放轨道异常'},
      );
      // coverage:ignore-end
    }
  }

  // ─── 缓冲补充 ─────────────────────────────────────────────

  /// 补充缓冲队列，下载一个音频文件。
  Future<void> _refillBuffer() async {
    if (_sentenceSource == null) return;
    final int currentSession = _session; // 捕获当前会话 ID
    final request = await _sentenceSource!.nextTtsSentence(currentSession);
    if (_disposed) return;
    if (request == null) {
      // 句子源已耗尽（章节末尾），退避等待，防止紧循环饿死 UI 事件循环
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return;
    }
    // 校验会话有效性（避免 nextTtsSentence 耗时过长导致 session 已变更）
    if (currentSession != _session) return;
    if (request.text.length < 5) return;

    final String? filePath;
    try {
      filePath = await _engine
          .downloadAudio(request)
          .timeout(const Duration(seconds: 15));
    } catch (e, st) {
      // 只有在会话未变更时才计入失败
      if (currentSession == _session) {
        _consecutiveFailures++;
        final threshold = _backgroundTolerant ? 30 : 8;
        if (_consecutiveFailures >= threshold) {
          CyberLogger.captureWarning(
            e is Exception ? e : Exception('$e'),
            stack: st,
            tag: 'tts',
            extra: {'context': '连续 8 次下载失败，触发降级'},
          );
          // P2 修复：同步置 isDegradedToLocal=true，防止 degradeToLocal 内部
          // `await stopAudio/pauseAudio` 完成前 _prefetchRunner 继续 loop 重复
          // 调用 _refillBuffer 累加 _consecutiveFailures、重复触发 degradeToLocal。
          _fallback.isDegradedToLocal = true;
          _fallback.degradeToLocal(request);
        }
      }
      return;
    }

    if (_disposed || currentSession != _session) {
      if (filePath != null) _deleteFile(filePath);
      return;
    }
    if (filePath == null) {
      _consecutiveFailures++;
      final threshold = _backgroundTolerant ? 30 : 6;
      if (_consecutiveFailures >= threshold) {
        CyberLogger.captureWarning(
          Exception('download returned null'),
          tag: 'tts',
          extra: {'context': '连续 3 次返回空路径'},
        );
        // P2 修复：同上，同步置标志位防止 _prefetchRunner 在 degradeToLocal
        // chain 完成前重复入循环。
        _fallback.isDegradedToLocal = true;
        _fallback.degradeToLocal(request);
      }
      return;
    }

    _consecutiveFailures = 0;
    _buffer.add(
      BufferedAudio(
        filePath: filePath,
        lineIndex: request.lineIndex,
        endLineIndex: request.endLineIndex,
        text: request.text,
        title: request.title,
        session: currentSession,
      ),
    );
  }

  // ─── 播放与播后清理 ───────────────────────────────────────

  /// 播放下一句，播完后自动销毁临时文件。
  Future<void> _playNext() async {
    final item = _buffer.takeNext();
    if (item == null || _disposed) return;

    _resetIdleTimer(); // 每次开始新的一句，刷新计时

    // 🔥 Session 哨兵：如果音频项属于旧会话，直接丢弃
    if (item.session != _session) {
      _deleteFile(item.filePath);
      return;
    }

    final startItem = TtsAudioItem(
      id: DateTime.now().microsecondsSinceEpoch,
      session: _session,
      lineIndex: item.lineIndex,
      endLineIndex: item.endLineIndex,
      text: item.text,
      title: item.title,
      estimatedDuration: const Duration(seconds: 5),
    );
    _currentItem = startItem;
    _currentFilePath = item.filePath;

    if (_sentenceSource != null) {
      unawaited(
        Future.microtask(() async {
          try {
            _sentenceSource!.onTtsItemStarted(startItem);
          } catch (e, st) {
            // coverage:ignore-start
            CyberLogger.captureWarning(
              e,
              stack: st,
              tag: 'tts',
              extra: {'context': 'onTtsItemStarted 回调异常'},
            );
            // coverage:ignore-end
          }
        }),
      );
    }

    _applyState(
      TtsAudioPlaying(
        item: snapshotOf(startItem),
        bufferedCount: _buffer.count,
        targetCount: _buffer.maxSize,
        playbackRate: _playbackRate,
        fallbackMessage: _fallbackMessage,
      ),
    );

    // 等待播放完成
    await _engine.playFile(
      item.filePath,
      onComplete: () {
        _onPlaybackComplete(startItem);
      },
    );

    if (_disposed) return;

    // P0-4：暂停中断时绝不能阅后即焚。
    //
    // pause() 通过 stopAudio() 强制 complete `_playCompleter` → playFile 提前返回。
    // 若此处直接 _deleteFile，下次 resume 时 _buffer.prepend 回的当前文件路径已不存在，
    // playFile 会因 file.exists()==false 立即 onComplete → _onPlaybackComplete 推进游标，
    // 导致用户发现暂停的句子被跳过。
    //
    // 判定方式：使用 `_currentFilePath` 作为"耐久"标识。
    // - 自然完成时，_onPlaybackComplete 会把 `_currentFilePath` 置 null（line 521）；
    // - 暂停中断时，_onPlaybackComplete 早返回，`_currentFilePath` 保持指向当前文件；
    // - 会话切换/全停时，_currentFilePath 也已被清为 null。
    // 因此 _currentFilePath 仍等于本次的 item.filePath ⇔ 暂停中断 → 保留文件。
    if (_currentFilePath == item.filePath) {
      // 保留文件供 resume 复用；最终清理由 stopAll() / refreshSession() / play() 重播完成时托管。
      return;
    }

    // 阅后即焚：删除已播完的临时文件
    _deleteFile(item.filePath);

    // 不再回落 Buffering —— 由 _playRunner 循环直接消费下一项
  }

  /// 播放完成回调：推进阅读进度，清除播放中状态。
  void _onPlaybackComplete(TtsAudioItem item) {
    // 1. 会话校验：旧会话的完成回调不予处理
    if (_disposed || item.session != _session) return;

    // 2. 暂停校验：如果是因暂停导致的 stopAudio()，不应推进进度
    if (_isPausing || _pausedGuard.isInterrupt(item)) {
      CyberLogger.captureMessage('[TTS] 暂停引起的播放中断，保留进度', tag: 'tts');
      _pausedGuard.clear();
      return;
    }

    if (_currentItem?.id == item.id) {
      _currentItem = null;
      _currentFilePath = null; // 同步清除，避免 play() 误判
    }
    if (_sentenceSource != null) {
      unawaited(
        Future.microtask(() async {
          try {
            _sentenceSource!.onTtsItemFinished(item);
          } catch (e, st) {
            // coverage:ignore-start
            CyberLogger.captureWarning(
              e,
              stack: st,
              tag: 'tts',
              extra: {'context': 'onTtsItemFinished 回调异常'},
            );
            // coverage:ignore-end
          }
        }),
      );
    }
  }

  /// 删除已播完的临时文件（阅后即焚）。
  void _deleteFile(String path) {
    unawaited(
      Future.microtask(() async {
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e, st) {
          // coverage:ignore-start
          CyberLogger.captureWarning(
            e,
            stack: st,
            tag: 'tts',
            extra: {'context': 'TTS 删除临时文件失败', 'path': path},
          );
          // coverage:ignore-end
        }
      }),
    );
  }

  // ─── 状态构造与推送 ─────────────────────────────

  void _applyState(TtsAudioState newState) {
    if (_disposed) return;
    state = newState;
    _playbackRate = newState.playbackRate;
    _fallbackMessage = newState.fallbackMessage;

    // 影子状态机映射：仅 _applyState 一处使用，inline 比抽 helper 更直观。
    final shadowState = switch (newState) {
      TtsAudioIdle() => TtsPlaybackState.disabled,
      TtsAudioBuffering() => TtsPlaybackState.buffering,
      TtsAudioPlaying() => TtsPlaybackState.playing,
      TtsAudioPaused() => TtsPlaybackState.paused,
      TtsAudioError() => TtsPlaybackState.error,
    };

    _engine.syncShadow(
      state: shadowState,
      session: _session,
      error: (newState is TtsAudioError) ? newState.message : null,
      item: _currentItem,
      fallbackMessage: _fallbackMessage,
    );
  }

  // ─── 对外暴露（供 UI/测试 读取） ──────────────────

  int get currentSession => _session;
  TtsAudioBuffer get buffer => _buffer;
  bool get isDegraded => _fallback.isDegradedToLocal;
}
