import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';
import 'package:yueyou/features/audio/domain/tts_audio_buffer.dart';
import 'package:yueyou/features/audio/domain/tts_audio_state.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';

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
  bool _isDegradedToLocal = false;
  bool _isPausing = false;
  Timer? _idleTimer; // 静默暂停计时器

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
    ref.listen(settingsProvider, (prev, next) {
      if (prev?.idleTimeout != next.idleTimeout) {
        _resetIdleTimer();
      }
    });

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
      debugPrint('[TTS] 静默暂停：检测到用户已空闲 ${minutes}m，自动执行停播');
      pause();
    });
  }

  // ─── 公开 API ──────────────────────────────────────────────

  /// 启动或恢复播放。
  void play() {
    if (_disposed) return;
    if (_sentenceSource == null) {
      setBusinessError('无法开启 TTS：请先导入书籍');
      return;
    }
    _consecutiveFailures = 0;
    _resetIdleTimer(); // 启动播放时激活计时器

    if (_currentFilePath != null) {
      // 恢复暂停：重播当前文件（pause 时用 stop 释放了播放器，无法 resume）
      _startPump(); // 先启动泵，_playRunner 会从缓冲区消费
      if (!_buffer.isEmpty) {
        // 缓冲区有下一项，直接播下一句
      } else {
        // 缓冲区空 → 重新入队当前文件
        _buffer.add(
          BufferedAudio(
            filePath: _currentFilePath!,
            lineIndex: _currentItem?.lineIndex ?? -1,
            text: _currentItem?.text ?? '',
            title: _currentItem?.title ?? '',
            session: _session,
          ),
        );
      }
      _applyState(
        TtsAudioPlaying(
          item: _snapshotOf(_currentItem!),
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
    _isPausing = true; // 开启暂停标识，阻止 _onPlaybackComplete 推进进度
    try {
      await _engine.stopAudio();
      await _engine.pauseAudio();
    } finally {
      _isPausing = false;
    }

    _applyState(
      TtsAudioPaused(
        item: _currentItem != null ? _snapshotOf(_currentItem!) : null,
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
    _isDegradedToLocal = false;
    _consecutiveFailures = 0;
    _applyState(
      TtsAudioIdle(playbackRate: _playbackRate, fallbackMessage: null),
    );
  }

  /// 切换播放倍速。
  void cycleSpeed() => _engine.cycleSpeed();

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
    _isDegradedToLocal = false;
    _consecutiveFailures = 0;
    _fallbackMessage = null;

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

  /// @deprecated 仅用于测试兼容，请直接使用 refreshSession。
  void setEnabled(bool enabled) {
    if (enabled) {
      _consecutiveFailures = 0;
      _session++;
      _isDegradedToLocal = false;
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
        if (_isDegradedToLocal) {
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }
        if (_buffer.needsRefill) {
          await _refillBuffer();
        } else {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    } catch (e) {
      debugPrint('[TTS] 预加载轨道异常: $e');
    }
  }

  /// 播放轨道：串行消费缓冲队列，播完即进入下一句，不回落 Buffering。
  Future<void> _playRunner() async {
    try {
      while (_pumpActive && !_disposed) {
        if (_isDegradedToLocal) {
          await _pumpDegraded();
          continue;
        }
        if (!_buffer.isEmpty) {
          await _playNext();
        } else {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }
    } catch (e) {
      debugPrint('[TTS] 播放轨道异常: $e');
    }
  }

  // ─── 缓冲补充 ─────────────────────────────────────────────

  /// 补充缓冲队列，下载一个音频文件。
  Future<void> _refillBuffer() async {
    if (_sentenceSource == null) return;
    final int currentSession = _session; // 捕获当前会话 ID
    final request = await _sentenceSource!.nextTtsSentence(currentSession);
    if (_disposed || request == null) return;
    // 校验会话有效性（避免 nextTtsSentence 耗时过长导致 session 已变更）
    if (currentSession != _session) return;
    if (request.text.length < 5) return;

    final String? filePath;
    try {
      filePath = await _engine.downloadAudio(request);
    } catch (e) {
      // 只有在会话未变更时才计入失败
      if (currentSession == _session) {
        _consecutiveFailures++;
        if (_consecutiveFailures >= 5) {
          CyberLogger.captureWarning(
            e is Exception ? e : Exception('$e'),
            tag: 'tts',
            extra: {'context': '连续 5 次下载失败，触发降级'},
          );
          _degradeToLocal(request);
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
      // 降级判定：针对新会话的前 3 次失败更加宽容
      if (_consecutiveFailures >= 3) {
        CyberLogger.captureWarning(
          Exception('download returned null'),
          tag: 'tts',
          extra: {'context': '连续 3 次返回空路径'},
        );
        _degradeToLocal(request);
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
        Future.microtask(() => _sentenceSource!.onTtsItemStarted(startItem)),
      );
    }

    _applyState(
      TtsAudioPlaying(
        item: _snapshotOf(startItem),
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

    // 阅后即焚：删除已播完的临时文件
    _deleteFile(item.filePath);

    // 不再回落 Buffering —— 由 _playRunner 循环直接消费下一项
  }

  /// 播放完成回调：推进阅读进度，清除播放中状态。
  void _onPlaybackComplete(TtsAudioItem item) {
    // 1. 会话校验：旧会话的完成回调不予处理
    if (_disposed || item.session != _session) return;

    // 2. 暂停校验：如果是因暂停导致的 stopAudio()，不应推进进度
    if (_isPausing) {
      debugPrint('[TTS] 暂停引起的播放中断，保留进度');
      return;
    }

    if (_currentItem?.id == item.id) {
      _currentItem = null;
      _currentFilePath = null; // 同步清除，避免 play() 误判
    }
    if (_sentenceSource != null) {
      unawaited(
        Future.microtask(() => _sentenceSource!.onTtsItemFinished(item)),
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
            debugPrint('[TTS] 已销毁临时文件: $path');
          }
        } catch (e) {
          debugPrint('[TTS] 删除临时文件失败: $e');
        }
      }),
    );
  }

  // ─── 降级与恢复 ───────────────────────────────────────────

  /// 降级到本地 TTS。
  ///
  /// 前置条件：先停用远程播放器，再启动本地降级，杜绝二重唱。
  Future<void> _degradeToLocal(TtsAudioRequest request) async {
    // 停用远程播放器，确保不二重唱
    await _engine.stopAudio();
    await _engine.pauseAudio();

    _isDegradedToLocal = true;
    _fallbackMessage = '网络音频加载失败，已切换至本地语音';
    CyberLogger.captureWarning(
      Exception('TTS degraded to local engine'),
      tag: 'tts',
    );

    final fallbackItem = TtsAudioItem(
      id: DateTime.now().microsecondsSinceEpoch,
      session: _session,
      lineIndex: request.lineIndex,
      endLineIndex: request.endLineIndex,
      text: request.text,
      title: request.title,
      estimatedDuration: const Duration(seconds: 5),
    );
    _currentItem = fallbackItem;

    if (_sentenceSource != null) {
      unawaited(
        Future.microtask(
          () => _sentenceSource!.onTtsItemStarted(fallbackItem),
        ),
      );
    }

    _applyState(
      TtsAudioPlaying(
        item: _snapshotOf(fallbackItem),
        bufferedCount: _buffer.count,
        targetCount: _buffer.maxSize,
        playbackRate: _playbackRate,
        fallbackMessage: _fallbackMessage,
      ),
    );

    final ok = await _engine.speakWithLocalTts(request.text);
    if (!_disposed && ok && _currentItem?.id == fallbackItem.id) {
      _currentItem = null;
      if (_sentenceSource != null) {
        unawaited(
          Future.microtask(
            () => _sentenceSource!.onTtsItemFinished(fallbackItem),
          ),
        );
      }
    }
  }

  /// 退化模式下的纯本地循环。
  Future<void> _pumpDegraded() async {
    if (_sentenceSource == null) return;
    final request = await _sentenceSource!.nextTtsSentence(_session);
    if (_disposed) return;
    if (request == null) {
      // 无更多内容 → 尝试切回远程
      _isDegradedToLocal = false;
      _consecutiveFailures = 0;
      _fallbackMessage = null;
      return;
    }
    await _degradeToLocal(request);
  }

  // ─── 状态构造与推送 ────────────────────────────────────────

  void _applyState(TtsAudioState newState) {
    if (_disposed) return;
    state = newState;
    _playbackRate = newState.playbackRate;
    _fallbackMessage = newState.fallbackMessage;

    _engine.syncShadow(
      state: _toEnginePlaybackState(newState),
      session: _session,
      error: (newState is TtsAudioError) ? newState.message : null,
      item: _currentItem,
      fallbackMessage: _fallbackMessage,
    );
  }

  TtsPlaybackState _toEnginePlaybackState(TtsAudioState audioState) {
    return switch (audioState) {
      TtsAudioIdle() => TtsPlaybackState.disabled,
      TtsAudioBuffering() => TtsPlaybackState.buffering,
      TtsAudioPlaying() => TtsPlaybackState.playing,
      TtsAudioPaused() => TtsPlaybackState.paused,
      TtsAudioError() => TtsPlaybackState.error,
    };
  }

  TtsAudioSnapshot _snapshotOf(TtsAudioItem item) {
    return TtsAudioSnapshot(
      id: item.id,
      session: item.session,
      lineIndex: item.lineIndex,
      title: item.title,
      // 提词器需要完整朗读文本（合并短句时常远超 20 字），不再截断
      textPreview: item.text,
    );
  }

  // ─── 对外暴露（供 UI/测试 读取） ──────────────────────────

  int get currentSession => _session;
  TtsAudioBuffer get buffer => _buffer;
  bool get isDegraded => _isDegradedToLocal;
}
