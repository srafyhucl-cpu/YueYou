import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:yueyou/core/constants/cyber_error_messages.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:yueyou/features/audio/domain/tts_audio_models.dart';
import 'package:yueyou/features/audio/domain/tts_audio_buffer.dart';
import '../../settings/providers/settings_provider.dart';
import '../../../core/config/tts_config.dart';
import '../../../core/utils/safe_string.dart';
import '../../../core/utils/tts_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:yueyou/features/audio/domain/tts_audio_models.dart';
export 'package:yueyou/features/audio/domain/tts_audio_buffer.dart'
    show TtsBufferStatus;

/// TTS 引擎全局 Provider（Riverpod 生命周期托管版）
///
/// - 通过 [ref.watch] 声明式依赖 [settingsProvider]，实现配置热更新
/// - 通过 [ref.onDispose] 自动回收引擎资源，消除手动 dispose 调用
/// - 通过 [ref.listen] 响应设置变更，替代手动 addListener/removeListener
final ttsEngineProvider = ChangeNotifierProvider<TtsEngineService>((ref) {
  final settings = ref.read(settingsProvider);
  final svc = TtsEngineService(settings, externalSettingsListener: false);
  // 注册 Riverpod 自动销毁钩子，消除双调用风险（幂等守卫见 dispose()）
  ref.onDispose(svc.dispose);
  // 监听设置变更，推送给引擎同步（替代 addListener 手动管理）
  ref.listen<SettingsProvider>(
    settingsProvider,
    (_, next) => svc.syncSettingsFromProvider(next),
  );
  return svc;
});

/// 抽象接口，用于测试时注入 Mock
abstract class TtsAudioPlayer {
  Future<void> setSource(Source source);
  Future<void> resume();
  Future<void> pause();
  Future<void> stop();
  Future<void> setVolume(double volume);
  Future<void> setPlaybackRate(double rate);
  Future<void> setAudioContext(AudioContext context);
  Stream<void> get onPlayerComplete;
  Stream<Duration> get onPositionChanged;
  Stream<Duration> get onDurationChanged;
  Future<void> dispose();
}

/// 抽象接口，用于测试时注入 Mock
abstract class TtsWakeLock {
  Future<void> enable();
  Future<void> disable();
}

/// 抽象接口，用于测试时注入 Mock - 本地 TTS 降级引擎
abstract class TtsFallbackEngine {
  Future<void> initialize();
  Future<void> speak(String text);
  Future<void> stop();
}

/// 生产环境实现：包装系统原生 FlutterTts
class _FlutterTtsFallbackEngine implements TtsFallbackEngine {
  final FlutterTts _tts = FlutterTts();
  Completer<void>? _currentSpeech;

  @override
  Future<void> initialize() async {
    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    _tts.setCompletionHandler(() {
      if (_currentSpeech?.isCompleted == false) {
        _currentSpeech?.complete();
      }
      _currentSpeech = null;
    });
    _tts.setErrorHandler((dynamic msg) {
      if (_currentSpeech?.isCompleted == false) {
        _currentSpeech?.completeError(Exception('FlutterTts: $msg'));
      }
      _currentSpeech = null;
    });
  }

  @override
  Future<void> speak(String text) async {
    _currentSpeech = Completer<void>();
    try {
      await _tts.speak(text);
    } catch (e) {
      if (_currentSpeech?.isCompleted == false) {
        _currentSpeech?.complete();
      }
      _currentSpeech = null;
      rethrow;
    }
    try {
      await _currentSpeech!.future.timeout(const Duration(seconds: 60));
    } on TimeoutException {
      debugPrint('⚠️ 本地 TTS 朗读超时');
    } catch (e) {
      debugPrint('⚠️ 本地 TTS 朗读错误: $e');
    }
  }

  @override
  Future<void> stop() async {
    if (_currentSpeech?.isCompleted == false) {
      _currentSpeech?.complete();
    }
    _currentSpeech = null;
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

/// 抽象接口，用于测试时注入 Mock
abstract class TtsHttpClient {
  Future<TtsHttpResponse> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  });
  Future<void> download(Uri url, String savePath);
}

class TtsHttpResponse {
  final int statusCode;
  final String body;

  const TtsHttpResponse({required this.statusCode, required this.body});
}

/// 生产环境实现：包装真实 AudioPlayer
class _RealAudioPlayer implements TtsAudioPlayer {
  final AudioPlayer _player;
  _RealAudioPlayer(this._player);
  @override
  Future<void> setSource(Source source) => _player.setSource(source);
  @override
  Future<void> resume() => _player.resume();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);
  @override
  Future<void> setPlaybackRate(double rate) => _player.setPlaybackRate(rate);
  @override
  Future<void> setAudioContext(AudioContext context) =>
      _player.setAudioContext(context);
  @override
  Stream<void> get onPlayerComplete => _player.onPlayerComplete;
  @override
  Stream<Duration> get onPositionChanged => _player.onPositionChanged;
  @override
  Stream<Duration> get onDurationChanged => _player.onDurationChanged;
  @override
  Future<void> dispose() => _player.dispose();
}

/// 生产环境实现：包装真实 WakelockPlus
class _RealWakeLock implements TtsWakeLock {
  @override
  Future<void> enable() => WakelockPlus.enable();
  @override
  Future<void> disable() => WakelockPlus.disable();
}

/// 抽象 HTTP 客户端接口
abstract class HttpClientInterface {
  Future<void> download(Uri url, String savePath);
  Future<String> postJson(Uri url, dynamic body);
}

/// 真实 HTTP 客户端实现
class _RealHttpClient implements HttpClientInterface {
  @override
  Future<void> download(Uri url, String savePath) async {
    final File targetFile = File(savePath);
    await targetFile.parent.create(recursive: true);

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      debugPrint('🌐 TTS 下载请求开始: $url');
      var currentUrl = url;
      HttpClientRequest request = await client.getUrl(currentUrl);
      HttpClientResponse response;
      int redirectCount = 0;
      const int maxRedirects = 5;
      do {
        response = await request.close().timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            debugPrint('🛑 TTS 下载外部超时保护触发: 超过15秒');
            throw TimeoutException('TTS 下载超时 (15秒)');
          },
        );
        if (response.statusCode >= 300 &&
            response.statusCode < 400 &&
            response.headers.value('location') != null &&
            redirectCount < maxRedirects) {
          currentUrl = Uri.parse(response.headers.value('location')!);
          debugPrint('🔄 TTS 下载重定向: $currentUrl');
          request = await client.getUrl(currentUrl);
          redirectCount++;
        } else {
          break;
        }
      } while (true);
      final int statusCode = response.statusCode;
      if (statusCode >= 400) {
        throw HttpException('下载音频失败: HTTP $statusCode');
      }
      final bytes = <int>[];
      debugPrint('📥 TTS 下载连接成功，等待数据传输: HTTP $statusCode');
      await for (final chunk in response) {
        bytes.addAll(chunk);
        debugPrint('📦 TTS 下载数据块接收: ${chunk.length} 字节，总计 ${bytes.length} 字节');
      }
      if (bytes.isEmpty) {
        throw const HttpException('下载音频失败: 响应体为空');
      }
      await targetFile.writeAsBytes(bytes, flush: true);
      debugPrint(
        '✅ TTS 下载响应完成: HTTP $statusCode, bytes=${bytes.length} -> $savePath',
      );
    } catch (e) {
      debugPrint('⚠️ TTS 下载异常: $e');
      rethrow;
    } finally {
      client.close();
    }
  }

  @override
  Future<String> postJson(Uri url, dynamic body) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(url);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      final Map<String, dynamic> bodyMap = body is Map<String, dynamic>
          ? body
          : (body is String ? jsonDecode(body) as Map<String, dynamic> : {});
      debugPrint('📡 TTS 请求 body: $bodyMap');
      final jsonBody = jsonEncode(bodyMap);
      request.write(jsonBody);
      final response = await request.close().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint('🛑 TTS POST 请求超时: 超过15秒');
          throw TimeoutException('TTS POST 请求超时 (15秒)');
        },
      );
      final responseBody = await response.transform(utf8.decoder).join();
      debugPrint('📡 TTS 响应: HTTP ${response.statusCode}');
      debugPrint('🔴 TTS 服务器原始响应内容: $responseBody');
      return responseBody;
    } finally {
      client.close();
    }
  }
}

/// 生产环境实现：包装真实 http.Client
class _RealTtsHttpClient implements TtsHttpClient {
  final HttpClientInterface _httpClient;

  _RealTtsHttpClient(this._httpClient);

  @override
  Future<TtsHttpResponse> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final responseBody = await _httpClient.postJson(url, body);
    final dynamic data = jsonDecode(responseBody);
    return TtsHttpResponse(
      statusCode: 200,
      body: data is String ? data : jsonEncode(data),
    );
  }

  @override
  Future<void> download(Uri url, String savePath) async {
    await _httpClient.download(url, savePath);
  }
}

/// TTS 音频播放状态机
///
/// Dart 3 模式匹配要求：所有 switch 必须穷尽以下 5 个分支：
/// - [disabled]：引擎关闭，不进行任何音频活动
/// - [paused]：已暂停，音频流挂起
/// - [buffering]：正在预加载下一句音频
/// - [playing]：正在播放音频
/// - [error]：引擎遭遇不可恢复错误（网络中断、格式异常等），
///            需用户手动恢复或等待自动降级
enum TtsPlaybackState { disabled, paused, buffering, playing, error }

/// 阅游 TTS 音频执行层
/// 架构：纯执行服务，由 TtsAudioNotifier 编排调度
class TtsEngineService extends ChangeNotifier {
  final TtsConfig _config;

  // 核心状态
  bool _disposed = false;

  late String _voice;
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
  String? _fallbackNotification;
  int _loopSession = 0;
  bool _wakeLockHeld = false;

  // 影子字段（由 TtsAudioNotifier 通过 syncShadow 驱动，保持 ReaderProvider 兼容）
  TtsAudioItem? _currentItem;

  // 空闲超时计时器
  Timer? _idleTimer;

  /// 当前播放任务的完成信号，用于外部强制停止（如切换发声人）
  Completer<void>? _playCompleter;

  /// 实时播放进度流 (0.0 -> 1.0)
  Stream<double> get progressStream => _progressController.stream;
  final _progressController = StreamController<double>.broadcast();
  Duration _currentDuration = Duration.zero;

  late final Future<void> _initFuture;
  bool _initCompleted = false;
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
    // ignore: unused_element
    Future<void> Function(Duration)? delayFn,
    TtsFallbackEngine? fallbackEngine,

    /// [externalSettingsListener]：是否由外部（Riverpod ref.listen）接管设置监听。
    /// - true（默认）：TtsEngineService 内部自行 addListener 监听 settings 变更（非 Riverpod 场景）。
    /// - false：由 ttsEngineProvider 的 ref.listen 统一推送，避免双重注册。
    bool externalSettingsListener = true,
  })  : _config = config ?? TtsConfig.current,
        _audioPlayer = audioPlayer ?? _RealAudioPlayer(AudioPlayer()),
        _wakeLock = wakeLock ?? _RealWakeLock(),
        _httpClient = httpClient ?? _RealTtsHttpClient(_RealHttpClient()),
        _fallbackEngine = fallbackEngine ?? _FlutterTtsFallbackEngine() {
    _settings = settings;
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

    // 绑定物理进度监听，实现提词器绝对同步
    _audioPlayer.onPositionChanged.listen((pos) {
      if (_currentDuration.inMilliseconds > 0) {
        final progress = pos.inMilliseconds / _currentDuration.inMilliseconds;
        _progressController.add(progress.clamp(0.0, 1.0));
      }
    });
    _audioPlayer.onDurationChanged.listen((dur) {
      _currentDuration = dur;
    });

    _initFuture = _initTtsHardware();
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
    if (!_initCompleted) {
      unawaited(_syncSettingsAfterInit());
      return;
    }
    _syncSettingsInternal(
      storyTts: _settings.storyTts,
      ttsRate: _settings.ttsRate,
      voice: _settings.voice,
      volume: _settings.ambientVol,
    );
  }

  Future<void> _syncSettingsAfterInit() async {
    await _initFuture;
    if (_disposed) return;
    if (!_initCompleted) return;
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
        debugPrint('设置播放倍速失败: $e');
      }),
    );
  }

  void _safeSetVolume(double volume) {
    unawaited(
      _audioPlayer.setVolume(volume).catchError((Object e) {
        _setLastError(CyberErrorMessages.ttsAudioParamFailed);
        debugPrint('设置音量失败: $e');
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

    if (_voice != voice) {
      _voice = voice;
    }
    // 语音/设置变更仅同步硬件参数，状态迁移由 TtsAudioNotifier 负责。
  }

  @override
  void dispose() {
    // 幂等守卫：防止 Riverpod ref.onDispose + 外部手动 dispose 双调用
    if (_disposed) return;
    _disposed = true;
    _settings.removeListener(_onSettingsChanged);
    _idleTimer?.cancel();
    _progressController.close();
    TtsCacheManager.instance.stopPeriodicClean();
    unawaited(_audioPlayer.dispose());
    unawaited(_fallbackEngine.stop());
    unawaited(_deleteFileIfExists(_lastGeneratedAudioPath));
    super.dispose();
  }

  Future<void> _initTtsHardware() async {
    try {
      await _cleanupOrphanedTtsFiles();

      _voice = _settings.voice;
      _volume = _settings.ambientVol;
      _playbackRate = _settings.ttsRate;

      await _audioPlayer.setVolume(_volume.clamp(0.0, 1.0));
      await _audioPlayer.setPlaybackRate(_playbackRate);

      _initCompleted = true;
      try {
        await _fallbackEngine.initialize();
      } catch (e) {
        debugPrint('⚠️ 本地 TTS 降级引擎初始化失败: $e');
      }
      debugPrint(' TTS 执行层已初始化');
    } catch (e) {
      debugPrint(' TTS 引擎初始化失败: $e');
      _initCompleted = true;
    }
  }

  Future<void> init() async {
    // 启动缓存定期清理（30 分钟间隔，跳过当前播放文件）
    TtsCacheManager.instance.startPeriodicClean(
      excludeActivePath: () => _lastGeneratedAudioPath,
    );
  }

  /// 任务 1.1：遍历临时目录，清理所有 tts_*.mp3 残留文件
  Future<void> _cleanupOrphanedTtsFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory(tempDir.path);
      if (!await dir.exists()) return;

      final entities = dir.listSync();
      int cleaned = 0;
      for (final entity in entities) {
        if (entity is File) {
          final name = entity.path.split(Platform.pathSeparator).last;
          // 匹配 tts_*.mp3 模式
          if (name.startsWith('tts_') && name.endsWith('.mp3')) {
            // 跳过当前 Session 正在使用的文件
            if (entity.path == _lastGeneratedAudioPath) continue;
            try {
              await entity.delete();
              cleaned++;
            } catch (_) {}
          }
        }
      }
      if (cleaned > 0) {
        debugPrint(' 已回收 $cleaned 个残留 TTS 临时文件');
      }
    } catch (e) {
      debugPrint(' 清理残留 TTS 文件失败: $e');
    }
  }

  /// API兼容层：写死返回音色列表
  Future<List<Map<String, String>>> getVoices() async {
    return [
      {'name': '默认女声', 'locale': 'zh-CN'},
      {'name': '温柔女声', 'locale': 'zh-CN'},
      {'name': '活力女声', 'locale': 'zh-CN'},
      {'name': '磁性男声', 'locale': 'zh-CN'},
    ];
  }

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
    _audioPlayer.setPlaybackRate(_playbackRate);
    _settings.setTtsRate(_playbackRate);
    notifyListeners();
  }

  void syncSpeedFromSettings(double logicalRate, double hardwareRate) {
    if (_playbackRate == logicalRate) return;
    _playbackRate = logicalRate;
    _audioPlayer.setPlaybackRate(logicalRate);
    notifyListeners();
  }

  // ─── 兼容字段与 getter（旧调用方/测试使用） ─────────────────────────

  /// @deprecated 缓冲管理已迁移至 TtsAudioNotifier + TtsAudioBuffer。
  int get bufferedCount => 0;
  double get bufferHealthRatio => 0.0;
  TtsBufferStatus get bufferStatus => TtsBufferStatus.empty;

  /// @deprecated 句子源管理已迁移至 TtsAudioNotifier.registerSentenceSource。
  Future<TtsAudioRequest?> Function(int session)? onNeedPrefetch;
  FutureOr<void> Function(TtsAudioItem item)? onItemStarted;
  FutureOr<void> Function(TtsAudioItem item)? onItemFinished;

  // ─── 兼容存根（旧调用方/测试使用，新代码走 TtsAudioNotifier） ────────

  /// 通知引擎有用户交互行为（兼容旧调用方）。
  void notifyUserActivity() {}

  /// @deprecated 使用 TtsAudioNotifier.setEnabled 替代。
  void setEnabled(bool enabled) {
    if (_disposed) return;
    _setLastError('TTS 状态管理已迁移，请通过音频面板控制');
  }

  /// @deprecated 使用 TtsAudioNotifier.refreshSession 替代。
  void refreshSession() {
    if (_disposed) return;
    _loopSession++;
    _audioPlayer.stop();
    syncShadow(state: TtsPlaybackState.disabled);
  }

  /// @deprecated 使用 TtsAudioNotifier.play 替代。
  void play() {
    if (_disposed) return;
    syncShadow(state: TtsPlaybackState.buffering);
  }

  /// @deprecated 使用 TtsAudioNotifier.pause 替代。
  Future<void> pause() async {
    if (_disposed) return;
    await _audioPlayer.pause();
    syncShadow(state: TtsPlaybackState.paused);
  }

  /// 停止所有音频播放（由 TtsAudioNotifier 在切换会话时调用）。
  Future<void> stopAll() async {
    _loopSession++;
    _idleTimer?.cancel();
    await Future.wait([
      _audioPlayer.stop(),
      _fallbackEngine.stop(),
    ]);
    _currentItem = null;
    syncShadow(state: TtsPlaybackState.disabled);
  }

  /// 🛠️ TTS 连接测试工具
  /// 返回详细的诊断信息，帮助排查问题
  Future<Map<String, dynamic>> testConnection() async {
    final String voice = _initCompleted ? _voice : _settings.voice;
    final result = <String, dynamic>{
      'success': false,
      'serverUrl': _config.serverUrl,
      'timestamp': DateTime.now().toIso8601String(),
      'steps': <Map<String, dynamic>>[],
    };

    try {
      // 步骤 1：检查服务器地址格式
      result['steps'].add({
        'step': 1,
        'name': '检查服务器地址',
        'status': 'success',
        'message': '服务器地址: ${_config.serverUrl}',
      });

      // 步骤 2：解析 URL
      final uri = Uri.parse(_config.serverUrl);
      result['steps'].add({
        'step': 2,
        'name': '解析 URL',
        'status': 'success',
        'message': 'Host: ${uri.host}, Port: ${uri.port}, Path: ${uri.path}',
      });

      // 步骤 3：发送 HTTP 请求
      const testText = '测试文本一二三四五';
      debugPrint('📡 发送 TTS 测试请求: $testText');

      // 使用注入的 httpClient 以确保可测试性
      final response = await _httpClient
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': testText, 'voice': voice}),
          )
          .timeout(_config.requestTimeout);

      result['statusCode'] = response.statusCode;
      result['responseSize'] = response.body.length;

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException(CyberErrorMessages.ttsNotJsonObject);
        }
        final String status = (decoded['status'] as String? ?? '').trim();
        final String audioUrl = (decoded['url'] as String? ?? '').trim();
        if (status != 'success' || audioUrl.isEmpty) {
          throw FormatException(
              CyberErrorMessages.ttsMissingUrlTest(response.body));
        }

        result['steps'].add({
          'step': 3,
          'name': 'HTTP 请求',
          'status': 'success',
          'message': '状态码: ${response.statusCode}, 已获取音频 URL',
        });

        result['steps'].add({
          'step': 4,
          'name': '解析音频地址',
          'status': 'success',
          'message': 'URL: $audioUrl',
        });

        // 步骤 5：尝试下载并写入文件
        try {
          final tempDir = await getTemporaryDirectory();
          final testFile = File('${tempDir.path}/tts_test.mp3');
          await _httpClient.download(Uri.parse(audioUrl), testFile.path);
          final int fileSize = await testFile.length();

          result['steps'].add({
            'step': 5,
            'name': '下载并写入文件',
            'status': fileSize < 1024 ? 'warning' : 'success',
            'message': fileSize < 1024
                ? '警告：音频文件太小 (<1KB)，可能是错误响应'
                : '成功写入: ${testFile.path}',
          });

          // 清理测试文件
          await testFile.delete();
        } catch (e) {
          result['steps'].add({
            'step': 5,
            'name': '下载并写入文件',
            'status': 'error',
            'message': '写入文件失败: $e',
          });
        }

        result['success'] = true;
        result['message'] = 'TTS 服务器连接成功！';
        _clearLastError();
      } else {
        result['steps'].add({
          'step': 3,
          'name': 'HTTP 请求',
          'status': 'error',
          'message': '服务器返回错误: ${response.statusCode}\n响应: ${response.body}',
        });
        result['statusCode'] = response.statusCode;
        result['message'] =
            CyberErrorMessages.ttsServerErrorCode(response.statusCode);
        _setLastError(response.statusCode);
      }
    } on TimeoutException catch (e) {
      result['steps'].add({
        'step': 3,
        'name': 'HTTP 请求',
        'status': 'error',
        'message': '请求超时: $e',
      });
      result['message'] = CyberErrorMessages.ttsRequestTimeout;
      _setLastError(e);
    } on SocketException catch (e) {
      result['steps'].add({
        'step': 3,
        'name': 'HTTP 请求',
        'status': 'error',
        'message': '网络错误: $e',
      });
      result['message'] = CyberErrorMessages.ttsConnectTimeout;
      _setLastError(e);
    } catch (e) {
      result['steps'].add({
        'step': 3,
        'name': 'HTTP 请求',
        'status': 'error',
        'message': '未知错误: $e',
      });
      result['message'] = '测试失败: $e';
      _setLastError(e);
    }

    return result;
  }

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

  /// 使用本地 TTS 引擎朗读指定文本，返回是否成功。
  Future<bool> _speakWithLocalTts(String text) async {
    try {
      await _fallbackEngine.speak(text);
      _clearLastError();
      return true;
    } catch (e) {
      debugPrint('⚠️ 本地 TTS 降级朗读失败: $e');
      return false;
    }
  }

  Future<void> _deleteFileIfExists(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
    if (_lastGeneratedAudioPath == path) {
      _lastGeneratedAudioPath = null;
    }
  }

  /// 使用本地 TTS 引擎朗读指定文本。
  Future<bool> speakWithLocalTts(String text) async {
    return _speakWithLocalTts(text);
  }

  /// 下载 TTS 音频文件（带重试机制），返回文件路径或 null。
  Future<String?> downloadAudio(TtsAudioRequest request) async {
    for (int attempt = 0; attempt < _config.maxRetries; attempt++) {
      try {
        final result = await _executeDownload(request, attempt);
        if (result != null) return result;
      } on TimeoutException catch (e) {
        _setLastError(e);
        debugPrint('[TTS] 请求超时 (尝试${attempt + 1}): $e');
        if (attempt < _config.maxRetries - 1) {
          await Future.delayed(_config.baseRetryDelay * (1 << attempt));
        }
      } catch (e) {
        _setLastError(e);
        debugPrint('[TTS] 下载失败 (尝试${attempt + 1}): $e');
        if (e is! FormatException && attempt < _config.maxRetries - 1) {
          await Future.delayed(_config.baseRetryDelay * (1 << attempt));
        } else if (e is FormatException) {
          break;
        }
      }
    }
    // 所有重试均失败 → Sentry 上报
    CyberLogger.captureWarning(
      Exception('TTS download failed after $_config.maxRetries retries'),
      tag: 'tts',
    );
    _setFallbackNotification(CyberErrorMessages.ttsFallbackDisconnected);
    return null;
  }

  /// 下载的单一尝试，返回文件路径或 null。
  ///
  /// 优先在后台 Isolate 中执行 HTTP 下载；若 Isolate 失败（如 Android
  /// 部分版本限制），自动降级到主线程 [TtsHttpClient] 重试。
  Future<String?> _executeDownload(TtsAudioRequest request, int attempt) async {
    final voice = _initCompleted ? _voice : _settings.voice;
    final serverUrl = _config.serverUrl;
    final isolateInput = _IsolateDownloadInput(
      text: request.text,
      voice: voice,
      serverUrl: serverUrl,
    );
    String? filePath;

    // 通道 1：Isolate 后台下载
    try {
      filePath = await Isolate.run(() => _isolateDownload(isolateInput));
      debugPrint('[TTS] Isolate 下载完成: $filePath');
    } catch (e) {
      debugPrint('[TTS] Isolate 下载失败 (尝试${attempt + 1}): $e');
      // 通道 2：降级到主线程 HTTP 客户端
      debugPrint('[TTS] 切换到主线程 HTTP 客户端重试');
      try {
        filePath = await _mainThreadDownload(request, voice, serverUrl);
      } catch (e2) {
        debugPrint('[TTS] 主线程下载也失败: $e2');
        if (e2 is FormatException) rethrow;
        _setLastError(e2);
        return null;
      }
    }

    if (_disposed) {
      unawaited(_deleteFileIfExists(filePath));
      return null;
    }
    if (filePath == null) return null;
    _lastGeneratedAudioPath = filePath;
    _clearLastError();
    return filePath;
  }

  /// 主线程 HTTP 客户端下载（Isolate 失败时的降级通道）。
  Future<String?> _mainThreadDownload(
      TtsAudioRequest request, String voice, String serverUrl) async {
    final uri = Uri.parse(serverUrl);
    final response = await _httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'text': request.text,
        'voice': voice,
      }),
    );
    if (_disposed) return null;
    if (response.statusCode != 200) {
      _setLastError(response.statusCode);
      return null;
    }
    final responseBody = response.body.trim();
    if (!(responseBody.startsWith('{') || responseBody.startsWith('['))) {
      throw const FormatException(CyberErrorMessages.ttsInvalidFormat);
    }
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(CyberErrorMessages.ttsNotJsonObject);
    }
    final status = (decoded['status'] as String? ?? '').trim();
    final audioUrl = (decoded['url'] as String? ?? '').trim();
    if (status != 'success' || audioUrl.isEmpty) {
      throw FormatException(CyberErrorMessages.ttsMissingUrl(responseBody));
    }
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = '${tempDir.path}/tts_$timestamp.mp3';
    await _httpClient.download(Uri.parse(audioUrl), filePath);
    return filePath;
  }

  /// 播放指定的本地音频文件。
  ///
  /// [path] 是本地临时文件路径，[onComplete] 在播放正常结束或出错时调用。
  Future<void> playFile(String path, {void Function()? onComplete}) async {
    try {
      // 物理进度归零，确保提词器扫光从头开始
      _currentDuration = Duration.zero;
      _progressController.add(0.0);

      // 先停止当前播放，确保播放器处于干净状态（避免 MEDIA_ERROR_SERVER_DIED）
      await _audioPlayer.stop();
      // 检查文件是否存在且有效
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('[TTS] 文件不存在，跳过播放: $path');
        onComplete?.call();
        return;
      }
      final fileSize = await file.length();
      if (fileSize < 1024) {
        debugPrint('[TTS] 文件太小 (${fileSize}B < 1KB)，跳过播放');
        onComplete?.call();
        return;
      }
      await _audioPlayer.setSource(DeviceFileSource(path)).timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw TimeoutException('setSource 超时'),
          );
      if (_disposed) return;
      _playCompleter = Completer<void>();
      final sub = _audioPlayer.onPlayerComplete.listen((_) {
        if (_playCompleter?.isCompleted == false) _playCompleter?.complete();
      });
      try {
        await _audioPlayer.resume();
        debugPrint('[TTS] AudioPlayer 已启动: $path');
        // 等待播放自然完成，或被 stopAudio 强制完成
        await _playCompleter!.future.timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            debugPrint('[TTS] 播放超时 (30s)，强制结束');
            unawaited(_audioPlayer.stop());
          },
        );
        _syncWakeLock(false);
        onComplete?.call();
      } finally {
        await sub.cancel();
        _playCompleter = null;
      }
    } on TimeoutException catch (e) {
      debugPrint('[TTS] 音频加载超时: $e');
      CyberLogger.captureWarning(
        e,
        tag: 'tts',
        extra: {'context': 'playFile 超时，播放熔断'},
      );
      await _audioPlayer.stop();
      _setLastError(CyberErrorMessages.ttsAudioLoadTimeout);
      onComplete?.call();
    } catch (e) {
      debugPrint('[TTS] 播放异常: $e');
      CyberLogger.captureWarning(
        e is Exception ? e : Exception('$e'),
        tag: 'tts',
        extra: {'context': 'playFile 异常'},
      );
      // 尝试停止播放器，出错时静默处理
      try {
        await _audioPlayer.stop();
      } catch (_) {}
      onComplete?.call();
    }
  }

  /// 恢复音频播放（已暂停时）。
  Future<void> resumeAudio() async => _audioPlayer.resume();

  /// 暂停音频播放。
  Future<void> pauseAudio() async {
    await Future.wait([
      _audioPlayer.pause(),
      _fallbackEngine.stop(),
    ]);
  }

  /// 停止所有音频播放。
  Future<void> stopAudio() async {
    // 1. 强制释放 playFile 的 await 阻塞
    if (_playCompleter?.isCompleted == false) {
      _playCompleter?.complete();
    }
    // 2. 底层硬件停播
    await Future.wait([
      _audioPlayer.stop(),
      _fallbackEngine.stop(),
    ]);
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
      _syncWakeLock(state == TtsPlaybackState.playing ||
          state == TtsPlaybackState.buffering);
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
    if (changed) notifyListeners();
  }
}

/// Isolate 下载输入参数（纯数据，可跨 Isolate 传递）。
class _IsolateDownloadInput {
  final String text;
  final String voice;
  final String serverUrl;

  const _IsolateDownloadInput({
    required this.text,
    required this.voice,
    required this.serverUrl,
  });
}

/// 在后台 Isolate 中执行的 TTS 音频下载流程。
///
/// 1. POST 请求获取音频 URL
/// 2. GET 下载二进制流
/// 3. 写入临时文件
/// 4. 返回文件路径
///
/// 独立于主 Isolate，不阻塞 UI 线程。
Future<String> _isolateDownload(_IsolateDownloadInput input) async {
  final client = HttpClient();
  try {
    // Step 1: POST → 获取音频 URL
    final postUri = Uri.parse(input.serverUrl);
    final postRequest = await client.postUrl(postUri);
    postRequest.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/json; charset=utf-8',
    );
    postRequest.write(jsonEncode({
      'text': input.text,
      'voice': input.voice,
    }));
    final postResponse = await postRequest.close().timeout(
          const Duration(seconds: 15),
        );
    if (postResponse.statusCode != 200) {
      throw HttpException('服务器返回 ${postResponse.statusCode}');
    }
    final responseBody = await postResponse.transform(utf8.decoder).join();
    if (!(responseBody.startsWith('{') || responseBody.startsWith('['))) {
      throw const FormatException('服务端响应格式异常');
    }
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('服务端响应非 JSON 对象');
    }
    final status = (decoded['status'] as String? ?? '').trim();
    final audioUrl = (decoded['url'] as String? ?? '').trim();
    if (status != 'success' || audioUrl.isEmpty) {
      throw FormatException(
          '音频 URL 缺失: ${safeSubstring(responseBody, 0, 100)}');
    }

    // Step 2: GET → 下载音频二进制
    final audioUri = Uri.parse(audioUrl);
    final audioRequest = await client.getUrl(audioUri);
    final audioResponse = await audioRequest.close().timeout(
          const Duration(seconds: 15),
        );
    if (audioResponse.statusCode >= 400) {
      throw HttpException('音频下载失败: HTTP ${audioResponse.statusCode}');
    }
    final bytes = <int>[];
    await for (final chunk in audioResponse) {
      bytes.addAll(chunk);
    }
    if (bytes.isEmpty) {
      throw const HttpException('音频内容为空');
    }

    // Step 3: 写入临时文件
    final tempDir = Directory.systemTemp;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = '${tempDir.path}/tts_$timestamp.mp3';
    await File(filePath).writeAsBytes(bytes, flush: true);

    return filePath;
  } finally {
    client.close();
  }
}
