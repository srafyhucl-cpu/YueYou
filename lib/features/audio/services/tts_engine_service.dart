import 'dart:async';
import 'dart:io' show HttpException, SocketException;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'package:yueyou/core/config/tts_config.dart';
import 'package:yueyou/core/constants/cyber_error_messages.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';
import 'package:yueyou/core/utils/tts_cache_manager.dart';
import 'package:yueyou/features/audio/domain/tts_audio_buffer.dart';
import 'package:yueyou/features/audio/domain/tts_audio_models.dart';
import 'package:yueyou/features/audio/domain/tts_engine_interfaces.dart';
import 'package:yueyou/features/audio/domain/tts_http_models.dart';
import 'package:yueyou/features/audio/domain/tts_network_interfaces.dart';
import 'package:yueyou/features/audio/services/tts_audio_adapters.dart';
import 'package:yueyou/features/audio/services/tts_audio_downloader.dart';
import 'package:yueyou/features/audio/services/tts_audio_janitor.dart';
import 'package:yueyou/features/audio/services/tts_diagnostics_service.dart';
import 'package:yueyou/features/audio/services/tts_http_client.dart';
import 'package:yueyou/features/audio/services/tts_playback_controller.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';

export 'package:yueyou/features/audio/domain/tts_audio_models.dart';
export 'package:yueyou/features/audio/domain/tts_audio_buffer.dart'
    show TtsBufferStatus;
export 'package:yueyou/features/audio/domain/tts_http_models.dart';
export 'package:yueyou/features/audio/domain/tts_engine_interfaces.dart';
export 'package:yueyou/features/audio/domain/tts_network_interfaces.dart';
export 'package:yueyou/features/audio/providers/tts_engine_provider.dart'
    show ttsEngineProvider;

/// 阅游 TTS 音频执行层
/// 架构：纯执行服务，由 TtsAudioNotifier 编排调度
class TtsEngineService extends ChangeNotifier {
  final TtsConfig _config;

  // 核心状态
  bool _disposed = false;
  late final Future<void> Function(Duration) _delayFn;
  final Completer<void> _disposeCompleter = Completer<void>();

  String _voice = '';
  late double _volume;
  TtsPlaybackState _state = TtsPlaybackState.disabled;
  String? _lastError;
  int _errorTimestamp = 0;
  double _playbackRate = 1.0;
  final List<double> _speedTiers = [1.0, 1.2, 1.5, 2.0, 2.5, 0.7];

  // 执行层核心（通过接口抽象，支持测试注入）
  late final TtsAudioPlayer _audioPlayer;
  late final TtsWakeLock _wakeLock;
  late final TtsHttpClient _httpClient;
  late final TtsFallbackEngine _fallbackEngine;

  // 子系统（PR-C 抽出）：诊断 / 下载 由构造器注入依赖 callback 后构建，
  // 所有「写回引擎」的副作用都通过显式 callback 暴露，便于单元测试。
  late final TtsDiagnosticsService _diagnostics;
  late final TtsAudioDownloader _downloader;
  late final TtsPlaybackController _playback;
  String? _fallbackNotification;
  int _loopSession = 0;
  bool _wakeLockHeld = false;

  // 影子字段（由 TtsAudioNotifier 通过 syncShadow 驱动，保持 ReaderProvider 兼容）
  TtsAudioItem? _currentItem;

  /// 当前播放任务的完成信号，用于外部强制停止（如切换发声人）
  Stream<double> get progressStream => _progressController.stream;
  final _progressController = StreamController<double>.broadcast();

  /// 硬件初始化 Future，用于守卫异步初始化流程
  late final Future<void> _initFuture;
  bool _initCompleted = false;

  /// 引擎硬件初始化完成 Future（测试 / 集成测试可 await 等待 _volume / _playbackRate
  /// 等 late 字段就绪，避免在初始化未完成前调用 syncSettingsFromProvider 触发
  /// LateInitializationError）。生产环境通常无需显式等待，硬件初始化是 fire-and-forget。
  Future<void> get initialized => _initFuture;
  String? _lastGeneratedAudioPath;

  TtsPlaybackState get state => _state;

  /// 引擎是否处于「已启用」状态
  bool get isEnabled => _state != TtsPlaybackState.disabled;

  /// 是否正在播放
  bool get isPlaying => _state == TtsPlaybackState.playing;

  /// 是否已暂停
  bool get isPaused => _state == TtsPlaybackState.paused;

  /// 是否处于错误状态
  bool get isError => _state == TtsPlaybackState.error;
  String? get lastError => _lastError;
  int get errorTimestamp => _errorTimestamp;
  double get playbackRate => _playbackRate;
  int get currentSession => _loopSession;
  TtsAudioItem? get currentItem => _currentItem;

  /// 缓冲队列上限（来自 TtsConfig.maxPrefetchQueue，默认 6）。
  int get maxBufferedCount => _config.maxPrefetchQueue;

  late SettingsProvider _settings;

  TtsEngineService(
    SettingsProvider settings, {
    TtsConfig? config,
    TtsAudioPlayer? audioPlayer,
    TtsWakeLock? wakeLock,
    TtsHttpClient? httpClient,
    Future<void> Function(Duration)? delayFn,
    TtsFallbackEngine? fallbackEngine,

    /// [externalSettingsListener]：是否由外部（Riverpod ref.listen）接管设置监听。
    /// - true（默认）：TtsEngineService 内部自行 addListener 监听 settings 变更（非 Riverpod 场景）。
    /// - false：由 ttsEngineProvider 的 ref.listen 统一推送，避免双重注册。
    bool externalSettingsListener = true,
  })  : _config = config ?? TtsConfig.current,
        _audioPlayer = audioPlayer ?? RealAudioPlayer(AudioPlayer()),
        _wakeLock = wakeLock ?? RealWakeLock(),
        _httpClient = httpClient ?? RealTtsHttpClient(RealHttpClient()),
        _fallbackEngine = fallbackEngine ?? FlutterTtsFallbackEngine() {
    _delayFn = delayFn ?? (d) => Future<void>.delayed(d);
    _settings = settings;
    _voice = settings.voice;
    // 配置音频上下文：允许朗读与背景音共存（Ducking 策略）
    _audioPlayer.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          audioFocus: AndroidAudioFocus.gainTransient,
          contentType: AndroidContentType.speech,
          usageType: AndroidUsageType.assistanceAccessibility,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {
            AVAudioSessionOptions.mixWithOthers,
            AVAudioSessionOptions.duckOthers,
          },
        ),
      ),
    );

    _playback = TtsPlaybackController(
      audioPlayer: _audioPlayer,
      fallbackEngine: _fallbackEngine,
      isDisposed: () => _disposed,
      onError: _setLastError,
      progressEmitter: _progressController.add,
    );

    // 根据设置初始化状态，确保 isEnabled 同步正确
    if (_settings.storyTts) {
      _state = TtsPlaybackState.buffering;
    }

    _initFuture = _initTtsHardware();

    // 实例化子系统：诊断 / 下载。所有依赖与状态写回 callback 全部
    // 显式传递，便于 Mock 替换。
    _diagnostics = TtsDiagnosticsService(
      httpClient: _httpClient,
      config: _config,
      voiceGetter: () => _initCompleted ? _voice : _settings.voice,
      onError: _setLastError,
      onClearError: _clearLastError,
    );
    _downloader = TtsAudioDownloader(
      httpClient: _httpClient,
      fallbackEngine: _fallbackEngine,
      config: _config,
      voiceGetter: () => _initCompleted ? _voice : _settings.voice,
      initFuture: _initFuture,
      isDisposed: () => _disposed,
      delayFn: _delayFn,
      playbackRateGetter: () => _playbackRate,
      onError: _setLastError,
      onClearError: _clearLastError,
      onFallbackNotification: _setFallbackNotification,
      onPathGenerated: (path) => _lastGeneratedAudioPath = path,
      progressEmitter: _progressController.add,
    );

    // 非 Riverpod 场景（如测试直接构造），仍使用内部监听器
    if (externalSettingsListener) {
      _listenToSettings();
    }
  }

  /// 供 Riverpod ref.listen 调用：接收最新 SettingsProvider 实例并同步配置
  /// 替代手动 addListener，实现声明式依赖解耦。
  void syncSettingsFromProvider(SettingsProvider newSettings) {
    // 更新内部 settings 引用（Riverpod 可能重建 SettingsProvider）
    _settings = newSettings;
    _onSettingsChanged();
  }

  void _listenToSettings() {
    _settings.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    if (_disposed) return;

    if (_settings.voice != _voice) {
      _voice = _settings.voice;
      refreshSession();
    }

    _syncSettingsInternal(
      storyTts: _settings.storyTts,
      ttsRate: _settings.ttsRate,
      voice: _settings.voice,
      volume: _settings.ambientVol,
    );
  }

  void _safeSetPlaybackRate(double rate) {
    unawaited(
      _audioPlayer.setPlaybackRate(rate).catchError((Object e) {
        _setLastError(CyberErrorMessages.ttsAudioParamFailed);
        CyberLogger.captureWarning(
          e,
          tag: 'tts',
          extra: {'context': '设置播放倍速失败'},
        );
      }),
    );
  }

  void _safeSetVolume(double volume) {
    unawaited(
      _audioPlayer.setVolume(volume).catchError((Object e) {
        _setLastError(CyberErrorMessages.ttsAudioParamFailed);
        CyberLogger.captureWarning(
          e,
          tag: 'tts',
          extra: {'context': '设置音量失败'},
        );
      }),
    );
  }

  void _setLastError(dynamic error) {
    final message = switch (error) {
      final String msg => msg,
      TimeoutException _ => '接入链路波动，请检查网络',
      SocketException _ => '网络连接失败，请检查网络设置',
      HttpException _ => '服务器连接异常，请稍后重试',
      FormatException _ => '数据解析失败，请联系管理员',
      final int code => switch (code) {
          404 => '请求的资源不存在，请检查后重试',
          >= 500 => '服务器维护中，请稍后再试',
          >= 400 => '请求参数异常，请稍后重试',
          _ => '网络请求异常 ($code)',
        },
      _ => '系统服务异常，请稍后重试',
    };

    _lastError = message;
    _errorTimestamp = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }

  void _clearLastError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  /// 清理最近一次 TTS 错误，供 UI 层在提示后主动清空。
  void clearLastError() {
    _clearLastError();
  }

  /// 设置 TTS 错误信息，供外部模块（如 ReaderProvider 前置拦截）使用。
  void setLastError(dynamic error) {
    _setLastError(error);
  }

  String? get fallbackNotification => _fallbackNotification;

  void _setFallbackNotification(String message) {
    _fallbackNotification = message;
    notifyListeners();
  }

  /// 清理降级通知，供 UI 层在显示 Toast 后主动清空。
  void clearFallbackNotification() {
    _fallbackNotification = null;
  }

  void _syncSettingsInternal({
    required bool storyTts,
    required double ttsRate,
    required String voice,
    required double volume,
  }) {
    if (_playbackRate != ttsRate) {
      _playbackRate = ttsRate;
      _safeSetPlaybackRate(ttsRate);
    }

    if (_volume != volume) {
      _volume = volume.clamp(0.0, 1.0);
      _safeSetVolume(_volume);
    }

    // 语音/设置变更仅同步硬件参数，状态迁移由 TtsAudioNotifier 负责。
  }

  @override
  void dispose() {
    // 幂等守卫：防止 Riverpod ref.onDispose + 外部手动 dispose 双调用
    if (_disposed) return;
    _disposed = true;
    if (!_disposeCompleter.isCompleted) _disposeCompleter.complete();
    _settings.removeListener(_onSettingsChanged);
    _playback.dispose();
    _progressController.close();
    TtsCacheManager.instance.stopPeriodicClean();
    _wakeLockHeld = false;
    unawaited(_wakeLock.disable());
    unawaited(_audioPlayer.dispose());
    unawaited(_fallbackEngine.dispose());
    unawaited(_downloader.deleteFileIfExists(_lastGeneratedAudioPath));
    _lastGeneratedAudioPath = null;
    unawaited(_initFuture); // 确保初始化完成（即使是销毁时）
    super.dispose();
  }

  Future<void> _initTtsHardware() async {
    try {
      await cleanupOrphanedTtsFiles(
        activePathGetter: () => _lastGeneratedAudioPath,
      );

      _voice = _settings.voice;
      _volume = _settings.ambientVol;
      _playbackRate = _settings.ttsRate;

      await _audioPlayer.setVolume(_volume.clamp(0.0, 1.0));
      await _audioPlayer.setPlaybackRate(_playbackRate);

      _initCompleted = true;
      try {
        await _fallbackEngine.initialize();
      } catch (e, st) {
        CyberLogger.captureWarning(
          e,
          stack: st,
          tag: 'tts',
          extra: {'context': '本地 TTS 降级引擎初始化失败'},
        );
      }
      CyberLogger.captureMessage('TTS 执行层已初始化', tag: 'tts');
    } catch (e, st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'tts',
        extra: {'context': 'TTS 引擎初始化失败'},
      );
      _initCompleted = true;
    }
  }

  Future<void> init() async {
    // 启动缓存定期清理（30 分钟间隔，跳过当前播放文件）
    TtsCacheManager.instance.startPeriodicClean(
      excludeActivePath: () => _lastGeneratedAudioPath,
    );
  }

  /// 轻量 ping 探测：委托 [TtsDiagnosticsService] 检测服务端可达性。
  Future<bool> pingServer() => _diagnostics.pingServer();

  /// 手动触发 TTS 缓存清理（供设置页「清理缓存」按钮调用）
  ///
  /// 执行双重判定清理：超过 24 小时的文件 + 总大小超过 500MB 时按旧删。
  /// 跳过当前正在播放的文件，幂等安全。
  Future<TtsCacheCleanResult> cleanCacheNow() {
    return TtsCacheManager.instance.cleanNow(
      excludePath: _lastGeneratedAudioPath,
    );
  }

  /// 查询当前 TTS 缓存占用信息（不执行清理）
  Future<TtsCacheStat> getCacheStat() {
    return TtsCacheManager.instance.getStat();
  }

  void cycleSpeed() {
    final int currentIndex = _speedTiers.indexOf(_playbackRate);
    final int nextIndex = (currentIndex + 1) % _speedTiers.length;
    _playbackRate = _speedTiers[nextIndex];
    // P3 修复：统一走 `_safeSetPlaybackRate`（内部 `unawaited(.catchError)`），
    // 与 `_syncSettingsInternal` 的容错口径一致：播放器底层故障时必走
    // `_setLastError + captureWarning`，不向 UI 层抛出未处理异常导致红屏。
    _safeSetPlaybackRate(_playbackRate);
    _settings.setTtsRate(_playbackRate);
    notifyListeners();
  }

  void syncSpeedFromSettings(double logicalRate, double hardwareRate) {
    if (_playbackRate == logicalRate) return;
    _playbackRate = logicalRate;
    // P3 修复：同 `cycleSpeed`，改走 `_safeSetPlaybackRate` 统一容错。
    _safeSetPlaybackRate(logicalRate);
    notifyListeners();
  }

  // ─── 兼容字段与 getter（旧调用方/测试使用） ─────────────────────────
  final List<String> _compatBuffer = [];

  /// @deprecated 缓冲管理已迁移至 TtsAudioNotifier + TtsAudioBuffer。
  int get bufferedCount => _compatBuffer.length;

  double get bufferHealthRatio {
    // 保护：如果队列上限为 0，视为健康度满分（1.0），防止除零
    if (_config.maxPrefetchQueue <= 0) return 1.0;
    return (bufferedCount / _config.maxPrefetchQueue).clamp(0.0, 1.0);
  }

  TtsBufferStatus get bufferStatus {
    if (bufferedCount == 0) return TtsBufferStatus.empty;
    final ratio = bufferHealthRatio;
    if (ratio >= 0.6) return TtsBufferStatus.healthy;
    if (ratio >= 0.33) return TtsBufferStatus.warning;
    return TtsBufferStatus.critical;
  }

  /// @deprecated 句子源管理已迁移至 TtsAudioNotifier.registerSentenceSource。
  Future<TtsAudioRequest?> Function(int session)? onNeedPrefetch;
  FutureOr<void> Function(TtsAudioItem item)? onItemStarted;
  FutureOr<void> Function(TtsAudioItem item)? onItemFinished;

  // ─── 兼容存根（旧调用方/测试使用，新代码走 TtsAudioNotifier） ────────

  /// 通知引擎有用户交互行为，触发监听者（TtsAudioNotifier）重置计时器。
  void notifyUserActivity() {
    notifyListeners();
  }

  /// @deprecated 使用 TtsAudioNotifier.setEnabled 替代。
  void setEnabled(bool enabled) {
    if (_disposed) return;
    if (enabled) {
      if (_state == TtsPlaybackState.disabled) {
        syncShadow(state: TtsPlaybackState.buffering);
      }
    } else {
      stopAll();
    }
  }

  /// @deprecated 使用 TtsAudioNotifier.refreshSession 替代。
  void refreshSession() {
    if (_disposed) return;
    _loopSession++;
    _audioPlayer.stop();
    _currentItem = null;
    syncShadow(state: TtsPlaybackState.disabled);
  }

  /// @deprecated 使用 TtsAudioNotifier.play 替代。
  Future<void> play() async {
    if (_disposed) return;
    if (_state == TtsPlaybackState.paused) {
      syncShadow(state: TtsPlaybackState.playing);
    } else if (_state == TtsPlaybackState.disabled) {
      syncShadow(state: TtsPlaybackState.buffering);
    }
  }

  /// @deprecated 使用 TtsAudioNotifier.pause 替代。
  Future<void> pause() async {
    if (_disposed) return;
    await _audioPlayer.pause();
    await _wakeLock.disable();
    syncShadow(state: TtsPlaybackState.paused);
  }

  /// 停止所有音频播放（由 TtsAudioNotifier 在切换会话时调用）。
  Future<void> stopAll() async {
    _loopSession++;
    await Future.wait([
      _audioPlayer.stop(),
      _fallbackEngine.stop(),
      _wakeLock.disable(),
    ]);
    _currentItem = null;
    syncShadow(state: TtsPlaybackState.disabled);
  }

  /// 🛠️ TTS 连接测试工具：委托 [TtsDiagnosticsService]，返回详细的诊断信息。
  Future<Map<String, dynamic>> testConnection() =>
      _diagnostics.testConnection();

  Future<void> _syncWakeLock(bool enable) async {
    if (_wakeLockHeld == enable) return;
    _wakeLockHeld = enable;
    try {
      if (enable) {
        await _wakeLock.enable();
      } else {
        await _wakeLock.disable();
      }
    } catch (_) {}
  }

  /// 使用本地 TTS 引擎朗读指定文本：委托 [TtsAudioDownloader]。
  Future<bool> speakWithLocalTts(String text) =>
      _downloader.speakWithLocalTts(text);

  /// 下载 TTS 音频文件（带重试机制）：委托 [TtsAudioDownloader]，
  /// 返回文件路径或 null。
  Future<String?> downloadAudio(TtsAudioRequest request) =>
      _downloader.downloadAudio(request);

  Future<void> playFile(String path, {void Function()? onComplete}) =>
      _playback.playFile(path, onComplete: onComplete);

  /// 恢复音频播放（已暂停时）。
  Future<void> resumeAudio() => _playback.resumeAudio();

  /// 暂停音频播放。
  Future<void> pauseAudio() => _playback.pauseAudio();

  /// 停止所有音频播放。
  Future<void> stopAudio() async {
    await _playback.stopAudio();
    _compatBuffer.clear();
  }

  /// 影子状态同步（由 [TtsAudioNotifier] 调用，保持向下兼容）。
  void syncShadow({
    TtsPlaybackState? state,
    int? session,
    String? error,
    TtsAudioItem? item,
    String? fallbackMessage,
  }) {
    bool changed = false;
    if (state != null && _state != state) {
      _state = state;
      _syncWakeLock(
        state == TtsPlaybackState.playing ||
            state == TtsPlaybackState.buffering,
      );
      changed = true;
    }
    if (session != null && _loopSession != session) {
      _loopSession = session;
    }
    if (error != null && _lastError != error) {
      _lastError = error;
      _errorTimestamp = DateTime.now().millisecondsSinceEpoch;
      changed = true;
    }
    if (error == null && _lastError != null) {
      _lastError = null;
      changed = true;
    }
    if (item != null || (item == null && _currentItem != null)) {
      _currentItem = item;
    }
    if (fallbackMessage != null) {
      _fallbackNotification = fallbackMessage;
      changed = true;
    } else if (fallbackMessage == null && _fallbackNotification != null) {
      _fallbackNotification = null;
    }
    if (changed && !_disposed) notifyListeners();
  }
}
