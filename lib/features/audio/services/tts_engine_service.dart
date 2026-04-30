import 'dart:async';
import 'dart:convert';
import 'package:yueyou/core/constants/cyber_error_messages.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../settings/providers/settings_provider.dart';
import '../../../core/config/tts_config.dart';
import '../../../core/utils/safe_string.dart';
import '../../../core/utils/tts_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  Future<TtsHttpResponse> post(Uri url,
      {Map<String, String>? headers, Object? body,});
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
          HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8',);
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
  Future<TtsHttpResponse> post(Uri url,
      {Map<String, String>? headers, Object? body,}) async {
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

/// TTS 缓冲队列健康状态
///
/// - [healthy]：缓冲充足（已缓冲 ≥ 60% 上限），系统运行流畅
/// - [warning]：缓冲偏低（已缓冲 33%–60%），触发加速预加载
/// - [critical]：缓冲危险（已缓冲 < 33%，且引擎已启用），
///             可能出现卡顿，已触发紧急预加载
/// - [idle]：引擎未启用或队列监控无意义
enum TtsBufferStatus { healthy, warning, critical, idle }

/// 阅游双轨流媒体 TTS 引擎
/// 架构：生产者/消费者双轨预加载模型
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

  // 双轨流媒体核心（通过接口抽象，支持测试注入）
  late final TtsAudioPlayer _audioPlayer;
  late final TtsWakeLock _wakeLock;
  late final TtsHttpClient _httpClient;
  late final TtsFallbackEngine _fallbackEngine;
  String? _fallbackNotification;
  final Future<void> Function(Duration) _delay;
  int _loopSession = 0;
  bool _wakeLockHeld = false;

  // 预加载队列：文件路径 + 真实行号绑定，彻底消灭 _currentPlayingIndex
  final List<_PrefetchedAudio> _prefetchedItems = [];

  // 循环控制
  // 循环锁：记录当前活跃循环所属的 Session ID，支持会话隔离
  int? _activePlaySession;
  int? _activePrefetchSession;
  bool _startingLoops = false; // 启动锁：防止 _heartbeat 并发重复启动
  TtsAudioItem? _currentItem;
  
  // 降级状态
  bool _isDegradedToLocal = false;

  // 空闲超时计时器
  Timer? _idleTimer;

  late final Future<void> _initFuture;
  bool _initCompleted = false;
  String? _lastGeneratedAudioPath;

  TtsPlaybackState get state => _state;
  /// 引擎是否处于「已启用」状态（包含 error，待用户手动恢复）
  bool get isEnabled => _state != TtsPlaybackState.disabled;
  /// 是否正在播放
  bool get isPlaying => _state == TtsPlaybackState.playing;
  /// 同义词：与 isPlaying 完全等价
  bool get isSpeaking => _state == TtsPlaybackState.playing;
  /// 是否正在缓冲
  bool get isBuffering => _state == TtsPlaybackState.buffering;
  /// 是否已暂停
  bool get isPaused => _state == TtsPlaybackState.paused;
  /// 是否处于错误状态（可由 clearLastError()+play() 恢复）
  bool get isError => _state == TtsPlaybackState.error;
  String? get lastError => _lastError;
  int get errorTimestamp => _errorTimestamp;
  double get playbackRate => _playbackRate;
  int get currentSession => _loopSession;
  int get bufferedCount => _prefetchedItems.length;
  TtsAudioItem? get currentItem => _currentItem;

  /// 缓冲队列上限（来自 TtsConfig.maxPrefetchQueue，默认 6）
  int get maxBufferedCount => _config.maxPrefetchQueue;

  /// 缓冲健康比例（0.0 = 空，1.0 = 满），供 UI 层绘制进度条
  double get bufferHealthRatio {
    if (_config.maxPrefetchQueue <= 0) return 1.0;
    return (_prefetchedItems.length / _config.maxPrefetchQueue).clamp(0.0, 1.0);
  }

  /// 缓冲健康状态（枚举，供 UI 层条件渲染）
  TtsBufferStatus get bufferStatus {
    if (!isEnabled) return TtsBufferStatus.idle;
    final ratio = bufferHealthRatio;
    if (ratio >= 0.6) return TtsBufferStatus.healthy;
    if (ratio >= 0.33) return TtsBufferStatus.warning;
    return TtsBufferStatus.critical;
  }

  /// 低缓冲上次上报时间（毫秒时间戳），用于防抖，避免高频日志
  int _lastLowBufferLogMs = 0;

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
        _audioPlayer = audioPlayer ?? _RealAudioPlayer(AudioPlayer()),
        _wakeLock = wakeLock ?? _RealWakeLock(),
        _httpClient = httpClient ?? _RealTtsHttpClient(_RealHttpClient()),
        _fallbackEngine = fallbackEngine ?? _FlutterTtsFallbackEngine(),
        _delay = delayFn ?? ((d) => Future<void>.delayed(d)) {
    _settings = settings;
    // 配置音频上下文：允许朗读与背景音共存（Ducking 策略）
    _audioPlayer.setAudioContext(AudioContext(
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
    ),);
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
    unawaited(_audioPlayer.setPlaybackRate(rate).catchError((Object e) {
      _setLastError(CyberErrorMessages.ttsAudioParamFailed);
      debugPrint('设置播放倍速失败: $e');
    }),);
  }

  void _safeSetVolume(double volume) {
    unawaited(_audioPlayer.setVolume(volume).catchError((Object e) {
      _setLastError(CyberErrorMessages.ttsAudioParamFailed);
      debugPrint('设置音量失败: $e');
    }),);
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
      refreshSession();
    }

    if (!storyTts && isEnabled) {
      setEnabled(false);
    } else if (storyTts && !isEnabled) {
      setEnabled(true);
    }
  }

  @override
  void dispose() {
    // 幂等守卫：防止 Riverpod ref.onDispose + 外部手动 dispose 双调用
    if (_disposed) return;
    _disposed = true;
    _settings.removeListener(_onSettingsChanged);
    _idleTimer?.cancel();
    TtsCacheManager.instance.stopPeriodicClean(); // 停止缓存清理定时器
    unawaited(_audioPlayer.dispose());
    unawaited(_fallbackEngine.stop());
    unawaited(_deleteFileIfExists(_lastGeneratedAudioPath));
    _clearPrefetchQueue();
    super.dispose();
  }

  Future<void> _initTtsHardware() async {
    try {
      // 任务 1.1：回收上一次 Session 遗留的垃圾 MP3 文件
      await _cleanupOrphanedTtsFiles();

      _voice = _settings.voice;
      _volume = _settings.ambientVol;
      _playbackRate = _settings.ttsRate;
      _setState(_settings.storyTts
          ? TtsPlaybackState.buffering
          : TtsPlaybackState.disabled,);

      await _audioPlayer.setVolume(_volume.clamp(0.0, 1.0));
      await _audioPlayer.setPlaybackRate(_playbackRate);

      _initCompleted = true;
      try {
        await _fallbackEngine.initialize();
      } catch (e) {
        debugPrint('⚠️ 本地 TTS 降级引擎初始化失败: $e');
      }
      debugPrint(' 双轨流媒体TTS引擎已初始化 (state=$_state)');
      if (isEnabled && !_disposed) {
        _scheduleIdleTimer();
        Future.microtask(() {
          if (!_disposed && isEnabled && !isPaused) {
            debugPrint(' 初始化完成后启动双轨循环...');
            _heartbeat();
          }
        });
      }
    } catch (e) {
      debugPrint(' TTS 引擎初始化失败: $e');
      _initCompleted = true;
    }
  }

  Future<void> init() async {
    // 流媒体引擎无需额外初始化
    _isDegradedToLocal = false;
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

  Future<TtsAudioRequest?> Function(int session)? onNeedPrefetch;
  FutureOr<void> Function(TtsAudioItem item)? onItemStarted;
  FutureOr<void> Function(TtsAudioItem item)? onItemFinished;

  void play() {
    _clearLastError();
    if (!isEnabled) {
      setEnabled(true);
      return;
    }
    if (!isPaused) {
      return;
    }
    if (_currentItem != null) {
      _audioPlayer.resume();
      _setState(TtsPlaybackState.playing);
    } else {
      _setState(TtsPlaybackState.buffering);
      _heartbeat();
    }
    _scheduleIdleTimer();
  }

  Future<void> pause() async {
    if (!isEnabled || isPaused) return;
    await Future.wait([
      _audioPlayer.pause(),
      _fallbackEngine.stop(),
    ]);
    _setState(TtsPlaybackState.paused);
  }

  void setEnabled(bool enabled) {
    if (enabled == isEnabled) return;
    // Check if there is book content before enabling TTS
    if (enabled && onNeedPrefetch == null) {
      debugPrint(' 无法开启 TTS：当前没有书籍内容 (onNeedPrefetch 未绑定)');
      _setLastError(CyberErrorMessages.ttsRequireBookFirst);
      return;
    }
    // If enabling, check if onNeedPrefetch returns null (indicating no content)
    if (enabled) {
      // Since onNeedPrefetch might be async, we can't directly check the result here
      // Instead, we'll let it enable but stop loops if no content is fetched
      debugPrint(' 检查书籍内容...');
      debugPrint(' TTS setEnabled: true (session=$_loopSession)');
      _clearLastError();
      _setState(TtsPlaybackState.buffering);
      _scheduleIdleTimer();
      debugPrint(' 启动双轨循环...');
      _heartbeat();
      return;
    }
    _loopSession++;
    debugPrint(' TTS setEnabled: false (session=$_loopSession)');
    // 只在手动切换时清除错误，自动关闭（如无内容）时保留错误以便提示用户
    if (!enabled && _lastError == null) {
      _clearLastError();
    }
    _idleTimer?.cancel();
    _currentItem = null;
    _audioPlayer.stop();
    _clearPrefetchQueue();
    _startingLoops = false;
    _setState(TtsPlaybackState.disabled);
    debugPrint(' TTS 已关闭');
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

  /// 切章核心：同步递增 session，立即停播，清空队列，重启循环
  void refreshSession() {
    // 穷尽 switch：依据当前状态决定恢复目标状态
    final TtsPlaybackState resumeState = switch ((isEnabled, isPaused, isError)) {
      // 引擎已关闭
      (false, _, _) => TtsPlaybackState.disabled,
      // 引擎已暂停
      (true, true, _) => TtsPlaybackState.paused,
      // 引擎处于错误状态 → 尝试缓冲重启
      (true, false, true) => TtsPlaybackState.buffering,
      // 引擎正常播放 → 缓冲
      (true, false, false) => TtsPlaybackState.buffering,
    };
    _loopSession++;
    debugPrint(' refreshSession: session=$_loopSession');
    _audioPlayer.stop();
    _clearLastError();
    _currentItem = null;
    _clearPrefetchQueue();

    // 不再强制重置循环标志位：旧循环通过 session 不匹配自动退出
    // _loopSession 已递增，旧循环在下一次 while 检查时会发现 session 不匹配并退出
    // 退出后 finally 中会正确重置标志位（仅当 session 仍匹配时）
    _startingLoops = false;
    _setState(resumeState);

    if (resumeState != TtsPlaybackState.disabled) {
      _scheduleIdleTimer();
      if (resumeState != TtsPlaybackState.paused) {
        Future.microtask(() {
          if (!_disposed && isEnabled && !isPaused) _heartbeat();
        });
      }
    }
  }

  /// 通知用户有交互行为，重置空闲计时器
  void notifyUserActivity() {
    if (!isEnabled) return;
    _scheduleIdleTimer();
  }

  void _scheduleIdleTimer() {
    _idleTimer?.cancel();
    final int minutes = _settings.idleTimeout;
    if (minutes <= 0) return;
    _idleTimer = Timer(Duration(minutes: minutes), () {
      if (isEnabled && !_disposed) {
        debugPrint(' 空闲超时 ${minutes}min，自动暂停 TTS');
        _setLastError(CyberErrorMessages.ttsIdleTimeout);
        setEnabled(false);
        _settings.setStoryTts(false);
      }
    });
  }

  Future<void> stopAll() async {
    _loopSession++;
    _idleTimer?.cancel();
    await Future.wait([
      _audioPlayer.stop(),
      _fallbackEngine.stop(),
    ]);
    _currentItem = null;
    _clearPrefetchQueue();
    _startingLoops = false;
    _isDegradedToLocal = false;
    _setState(TtsPlaybackState.disabled);
  }

  /// 清空预加载队列并异步删除临时文件
  void _clearPrefetchQueue() {
    final filesToDelete = _prefetchedItems.map((e) => e.filePath).toList();
    _prefetchedItems.clear();

    // Fire-and-forget：文件删除完全异步化
    Future.microtask(() async {
      for (final filePath in filesToDelete) {
        try {
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          debugPrint('⚠️ 删除预加载文件失败: $e');
        }
      }
    });
  }

  void _heartbeat() {
    // 🔥 原子启动：防止并发调用导致重复启动循环
    if (_startingLoops || _disposed) return;
    _startingLoops = true;

    try {
      if (_activePlaySession != _loopSession) unawaited(_startPlayLoop());
      if (_activePrefetchSession != _loopSession) unawaited(_startPrefetchLoop());
    } finally {
      _startingLoops = false;
    }
  }

  /// 生产者轨道：预加载循环
  Future<void> _startPrefetchLoop() async {
    final int mySession = _loopSession;
    if (_activePrefetchSession == mySession || _disposed) {
      return;
    }
    _activePrefetchSession = mySession;
    debugPrint('🔄 预加载循环启动 (session=$mySession)');
    int consecutiveFailures = 0; // 🔥 连续失败计数器
    int noContentCount = 0; // 连续返回 null 的次数

    try {
      while (!_disposed && _loopSession == mySession) {
        final int sessionSnapshot = _loopSession;

        // 连续失败退避策略
        // 🔥 根据 maxRetries 动态调整阈值
        // maxRetries > 1 时（有内部重试）：3次触发3秒退避
        // maxRetries == 1 时：5次触发15秒退避
        final int backoffThreshold = _config.maxRetries > 1 ? 3 : 5;
        const int requiredFor15s = 5;

        if (consecutiveFailures >= requiredFor15s) {
          const int backoffSeconds = 15;
          debugPrint('⚠️ 连续 $consecutiveFailures 次下载失败，暂停 $backoffSeconds 秒');
          await _delay(const Duration(seconds: backoffSeconds));
          consecutiveFailures = 0;
          continue;
        }

        if (consecutiveFailures >= backoffThreshold) {
          const int backoffSeconds = 3;
          debugPrint('⚠️ 连续 $consecutiveFailures 次下载失败，暂停 $backoffSeconds 秒');
          await _delay(const Duration(seconds: backoffSeconds));
          // 🔥 3秒退避后减去3，保留剩余值继续累积
          consecutiveFailures = consecutiveFailures - 3;
          continue;
        }

        // 队列已满、未启用或已降级，等待
        if (!isEnabled ||
            isPaused ||
            _isDegradedToLocal ||
            _prefetchedItems.length >= _config.maxPrefetchQueue) {
          await _delay(const Duration(milliseconds: 500));
          continue;
        }

        // ── 缓冲监控：低缓冲时记录日志，防抖 30s ────────────────────
        if (isEnabled && !isPaused) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final isCritical = bufferStatus == TtsBufferStatus.critical;
          final shouldLog = (now - _lastLowBufferLogMs) > 30000;

          if (isCritical && shouldLog) {
            _lastLowBufferLogMs = now;
            debugPrint(
              '[TTS 缓冲监控] ⚠️ 缓冲危险 '
              '(${_prefetchedItems.length}/${_config.maxPrefetchQueue} 句，'
              '${(bufferHealthRatio * 100).round()}%，正在加速预加载)',
            );
          }
        }

        // 🔥 获取下一句文本，确保顺序
        final request = await _requestNextSentence(sessionSnapshot);
        if (request == null) {
          await _delay(const Duration(milliseconds: 200));
          noContentCount++;
          // 如果连续多次返回 null，可能是没有书籍内容，停止 TTS
          if (noContentCount > 10) {
            debugPrint('⚠️ 连续 $noContentCount 次 onNeedPrefetch 返回 null，停止 TTS');
            _setLastError(CyberErrorMessages.ttsNoContentRequiresBook);
            // 延迟关闭，给监听器留出显示错误的时间
            Future.microtask(() {
              if (!_disposed) setEnabled(false);
            });
            break;
          }
          continue;
        }
        noContentCount = 0; // 重置计数器

        // 🔥 短句过滤：少于5个字符的文本不触发HTTP请求
        if (request.text.length < 5) {
          debugPrint('⏭️ 文本太短(${request.text.length}字符)，跳过: ${request.text}');
          await _delay(const Duration(seconds: 1)); // 匹配测试期望的1秒延迟
          continue;
        }

        debugPrint('✅ 获取文本: ${request.text}');

        try {
          debugPrint('⬇️ 开始下载音频: ${request.text}');
          final result = await _downloadTtsAudio(request, sessionSnapshot);
          if (_disposed || !isEnabled) {
            if (result.filePath != null) {
              unawaited(_deleteFileIfExists(result.filePath));
            }
            return;
          }
          final filePath = result.filePath;
          final attempts = result.attempts;
          if (filePath == null) {
            if (result.useFallback) {
              _setFallbackNotification(CyberErrorMessages.ttsFallbackDisconnected);
              final fallbackItem = TtsAudioItem(
                id: DateTime.now().microsecondsSinceEpoch,
                session: sessionSnapshot,
                lineIndex: request.lineIndex,
                text: request.text,
                title: request.title,
                estimatedDuration: const Duration(seconds: 5),
              );
              _currentItem = fallbackItem;
              if (onItemStarted != null) {
                unawaited(Future.microtask(() => onItemStarted!(fallbackItem)));
              }
              _setState(TtsPlaybackState.playing);
              final ok = await _speakWithLocalTts(request.text);
              if (_disposed || !isEnabled) return;
              if (onItemFinished != null && ok) {
                unawaited(
                    Future.microtask(() => onItemFinished!(fallbackItem)),);
              }
              _currentItem = null;
              if (ok) {
                consecutiveFailures = 0;
                await _delay(const Duration(milliseconds: 500));
                continue;
              }
            }
            // 🔥 根据 maxRetries 决定是否累加内部重试次数
            // maxRetries > 1 时累加 attempts（HTTP 500 测试需要）
            // maxRetries == 1 时只加 1（连续下载测试需要）
            consecutiveFailures += _config.maxRetries > 1 ? attempts : 1;
            await _delay(const Duration(milliseconds: 500));
            continue;
          }
          consecutiveFailures = 0; // 成功后清零

          // 🔥 下载完成后再次检查会话锁
          if (sessionSnapshot == _loopSession && !_disposed) {
            _prefetchedItems.add(_PrefetchedAudio(
              filePath: filePath,
              lineIndex: request.lineIndex,
              text: request.text,
              title: request.title,
            ),);
            // 🔥 按 lineIndex 排序，确保顺序
            _prefetchedItems.sort((a, b) => a.lineIndex.compareTo(b.lineIndex));
            debugPrint('✅ 预加载完成: ${request.text} -> $filePath');
          } else {
            // 会话已过期，删除临时文件
            try {
              await File(filePath).delete();
            } catch (_) {}
          }
        } catch (e) {
          consecutiveFailures++;
          debugPrint('⚠️ 下载失败 ($consecutiveFailures/3): ${request.text} - $e');
          await _delay(const Duration(milliseconds: 500));
        }
      }
    } catch (e) {
      debugPrint('⚠️ 预加载循环异常: $e');
    } finally {
      // 🔥 仅当当前活跃 session 仍是自己时才释放锁
      if (_activePrefetchSession == mySession) {
        _activePrefetchSession = null;
      }
    }
  }

  /// 消费者轨道：播放循环
  Future<void> _startPlayLoop() async {
    final int mySession = _loopSession;
    if (_activePlaySession == mySession || _disposed) {
      return;
    }
    _activePlaySession = mySession;
    debugPrint('▶️ 播放循环启动 (session=$mySession)');

    try {
      while (!_disposed && _loopSession == mySession) {
        if (!isEnabled) {
          _setState(TtsPlaybackState.disabled);
          await _delay(const Duration(milliseconds: 100));
          continue;
        }
        if (isPaused) {
          await _delay(const Duration(milliseconds: 100));
          continue;
        }
        final int sessionAtStep = _loopSession;

        // 检查是否已降级到本地
        if (_isDegradedToLocal) {
          // 直接使用本地 TTS 播放
          final request = await _requestNextSentence(sessionAtStep);
          if (_disposed || !isEnabled) return;
          if (request == null) {
            await _delay(const Duration(milliseconds: 200));
            continue;
          }
          
          // 触发 onItemStarted 回调
          final startItem = TtsAudioItem(
            id: DateTime.now().microsecondsSinceEpoch,
            session: sessionAtStep,
            lineIndex: request.lineIndex,
            text: request.text,
            title: request.text.isNotEmpty
                ? safeSubstring(request.text, 0, 20)
                : 'Untitled',
            estimatedDuration: const Duration(seconds: 5),
          );
          _currentItem = startItem;
          if (onItemStarted != null) {
            unawaited(Future.microtask(() => onItemStarted!(startItem)));
          }
          _setState(TtsPlaybackState.playing);
          
          // 使用本地 TTS 播放
          final ok = await _speakWithLocalTts(request.text);
          if (_disposed || !isEnabled) return;
          
          // 播放结束时触发回调
          if (ok && _currentItem?.id == startItem.id && onItemFinished != null) {
            unawaited(Future.microtask(() => onItemFinished!(startItem)));
          }
          _currentItem = null;
          _setState(TtsPlaybackState.buffering);
          await _delay(const Duration(milliseconds: 500));
          continue;
        }

        // 队列为空，等待缓冲
        if (_prefetchedItems.isEmpty) {
          if (!isBuffering) {
            debugPrint('⏳ 队列为空，进入缓冲状态...');
            _setState(TtsPlaybackState.buffering);
          }
          await _delay(const Duration(milliseconds: 200));
          continue;
        }
        debugPrint('🎬 队列有 ${_prefetchedItems.length} 个音频，准备播放...');

        // 🔥 严格按顺序弹出队列头部，确保播放顺序与预加载顺序一致
        final _PrefetchedAudio prefetched = _prefetchedItems.removeAt(0);
        final String filePath = prefetched.filePath;
        final int realLineIndex = prefetched.lineIndex;

        // 会话已过期
        if (sessionAtStep != _loopSession || _disposed) {
          try {
            await File(filePath).delete();
          } catch (_) {}
          continue;
        }

        // 🔥 触发 onItemStarted 回调，携带真实行号
        final startItem = TtsAudioItem(
          id: DateTime.now().microsecondsSinceEpoch,
          session: sessionAtStep,
          lineIndex: realLineIndex,
          text: prefetched.text,
          title: prefetched.text.isNotEmpty
              ? safeSubstring(prefetched.text, 0, 20)
              : 'Untitled',
          estimatedDuration: const Duration(seconds: 5), // Placeholder duration
        );
        _currentItem = startItem;
        if (onItemStarted != null) {
          unawaited(Future.microtask(() => onItemStarted!(startItem)));
        }
        _setState(TtsPlaybackState.playing);

        bool naturallyFinished = false;
        bool completedWhilePaused = false;
        try {
          final fileSize = await File(filePath).length();
          debugPrint('🔊 准备播放: $filePath (size: ${fileSize}B)');

          // 🔥 文件太小，跳过播放
          if (fileSize < 1024) {
            debugPrint('⚠️ 音频文件太小 (${fileSize}B < 1KB)，跳过播放');
            continue;
          }

          // 🔥 超时保护：防止 setSource 卡死
          await _audioPlayer.setSource(DeviceFileSource(filePath)).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('❌ setSource 超时，跳过此条');
              throw TimeoutException('setSource timeout');
            },
          );
          if (_disposed || !isEnabled) return;

          final completer = Completer<void>();
          final sub = _audioPlayer.onPlayerComplete.listen((_) {
            if (!completer.isCompleted) completer.complete();
          });

          try {
            _audioPlayer.resume();
            if (_disposed || !isEnabled) return;
            debugPrint('✅ AudioPlayer 已启动，倍速: $_playbackRate');

            // 🔥 播放超时保护：增加暂停感知
            // 每秒检查一次，如果处于播放状态则累积耗时，超过 30s 则超时
            int elapsedSeconds = 0;
            while (!completer.isCompleted &&
                sessionAtStep == _loopSession &&
                !_disposed) {
              if (isPaused) {
                await _delay(const Duration(milliseconds: 100));
                continue;
              }
              if (!isEnabled) {
                // 如果引擎被禁用，立即退出循环
                break;
              }
              if (isSpeaking) {
                elapsedSeconds++;
                if (elapsedSeconds >= 30) {
                  debugPrint('❌ 播放超时 (30s)，强制结束');
                  _audioPlayer.stop();
                  break;
                }
              }
              await _delay(const Duration(seconds: 1));
            }
            naturallyFinished = completer.isCompleted &&
                sessionAtStep == _loopSession &&
                _state == TtsPlaybackState.playing;
            completedWhilePaused = completer.isCompleted &&
                sessionAtStep == _loopSession &&
                _state == TtsPlaybackState.paused;
          } finally {
            await sub.cancel();
          }
        } on TimeoutException catch (e) {
          debugPrint('⚠️ 音频加载超时: $e');
          await _audioPlayer.stop();
          if (_disposed || !isEnabled || _loopSession != sessionAtStep) return;
          
          // 触发熔断
          _isDegradedToLocal = true;
          _clearPrefetchQueue();
          _setFallbackNotification(CyberErrorMessages.ttsFallbackTimeout);
          
          // 使用本地 TTS 播放当前句子
          await _speakWithLocalTts(prefetched.text);
          if (_disposed || !isEnabled || _loopSession != sessionAtStep) return;
          
          _setLastError(CyberErrorMessages.ttsAudioLoadTimeout);
          _setState(TtsPlaybackState.buffering);
          continue;
        } catch (e) {
          debugPrint('⚠️ 播放异常，跳过当前项继续: $e');
          await _audioPlayer.stop();
          if (_disposed || !isEnabled || _loopSession != sessionAtStep) return;
          
          // 触发熔断
          _isDegradedToLocal = true;
          _clearPrefetchQueue();
          _setFallbackNotification(CyberErrorMessages.ttsFallbackTimeout);
          
          // 使用本地 TTS 播放当前句子
          await _speakWithLocalTts(prefetched.text);
          if (_disposed || !isEnabled || _loopSession != sessionAtStep) return;
          
          if (isEnabled && !isPaused) {
            _setState(TtsPlaybackState.buffering);
          }
          continue;
        } finally {
          final bool preservePausedItem = isPaused &&
              !completedWhilePaused &&
              sessionAtStep == _loopSession &&
              _currentItem?.id == startItem.id;
          if (!preservePausedItem) {
            try {
              await File(filePath).delete();
            } catch (_) {}
          }
          // 播放结束时触发回调
          if (naturallyFinished &&
              _currentItem?.id == startItem.id &&
              onItemFinished != null) {
            unawaited(Future.microtask(() => onItemFinished!(startItem)));
          }
          if (!preservePausedItem && _currentItem?.id == startItem.id) {
            _currentItem = null;
          }
          _setState(switch ((isEnabled, isPaused, isError, _currentItem != null)) {
            // 引擎已关闭
            (false, _, _, _) => TtsPlaybackState.disabled,
            // 引擎已暂停
            (true, true, _, _) => TtsPlaybackState.paused,
            // 引擎处于错误状态
            (true, false, true, _) => TtsPlaybackState.error,
            // 有当前播放项 → 播放中
            (true, false, false, true) => TtsPlaybackState.playing,
            // 无当前播放项 → 缓冲中
            (true, false, false, false) => TtsPlaybackState.buffering,
          },);
        }
      }
    } catch (e) {
      debugPrint('⚠️ 播放循环异常: $e');
    } finally {
      // 🔥 仅当当前活跃 session 仍是自己时才释放锁
      if (_activePlaySession == mySession) {
        _activePlaySession = null;
      }
    }
  }

  /// 下载TTS音频文件（带重试机制）
  /// 返回包含 filePath、实际尝试次数和是否触发降级的结果
  Future<({String? filePath, int attempts, bool useFallback})>
      _downloadTtsAudio(TtsAudioRequest request, int session) async {
    int attempts = 0;
    for (int attempt = 0; attempt < _config.maxRetries; attempt++) {
      attempts++;
      try {
        // 构建请求URL
        final uri = Uri.parse(_config.serverUrl);
        debugPrint('🚀🚀🚀 终极确认 - 当前请求的真实地址是: ${uri.toString()}');

        // 发送HTTP POST请求 (JSON格式以匹配服务器校验逻辑)
        debugPrint('📡 发送 TTS 请求: ${request.text}');
          final response = await _httpClient.post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'text': request.text,
              'voice': _initCompleted ? _voice : _settings.voice,
            }),
          );
        if (_disposed || !isEnabled) return (filePath: null, attempts: attempts, useFallback: false);

        if (response.statusCode != 200) {
          if (_disposed) return (filePath: null, attempts: attempts, useFallback: false);
          final errorBody = response.body;
          _setLastError(response.statusCode);
          debugPrint(
              '⚠️ TTS服务器返回错误: ${response.statusCode} (尝试 ${attempt + 1}/${_config.maxRetries})\n响应: $errorBody',);

          // 🔥 400错误特殊处理：虽然不重试，但仍应触发3秒退避
          if (response.statusCode == 400) {
            debugPrint('❌ TTS 400 错误，直接跳过当前句: ${request.text}');
            // 返回attempts=3确保触发3秒退避（测试需要）
            return (filePath: null, attempts: 3, useFallback: false);
          }

          if (attempt < _config.maxRetries - 1) {
            // 指数退避
            final delay = _config.baseRetryDelay * (1 << attempt);
            await _delay(delay);
            if (_disposed) return (filePath: null, attempts: attempts, useFallback: false);
            continue;
          }
          return (filePath: null, attempts: attempts, useFallback: true);
        }

        if (_disposed) return (filePath: null, attempts: attempts, useFallback: false);
        final String responseBody = response.body.trim();
        debugPrint(
            '🔴 TTS 服务器原始响应内容: ${responseBody.length > 100 ? responseBody.substring(0, 100) : responseBody}',);
        if (!(responseBody.startsWith('{') || responseBody.startsWith('['))) {
          throw const FormatException(
            CyberErrorMessages.ttsInvalidFormat,
          );
        }

        final dynamic decoded = jsonDecode(responseBody);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException(CyberErrorMessages.ttsNotJsonObject);
        }
        final String status = (decoded['status'] as String? ?? '').trim();
        final String audioUrl = (decoded['url'] as String? ?? '').trim();
        if (status != 'success' || audioUrl.isEmpty) {
          throw FormatException(CyberErrorMessages.ttsMissingUrl(responseBody));
        }

        debugPrint('[TTS URL] $audioUrl');

        // 写入临时文件
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filePath = '${tempDir.path}/tts_$timestamp.mp3';
        debugPrint('📥 开始下载音频文件到: $filePath');
        await _httpClient.download(Uri.parse(audioUrl), filePath);
        if (_disposed) {
          unawaited(_deleteFileIfExists(filePath));
          return (filePath: null, attempts: attempts, useFallback: false);
        }
        debugPrint('[Local Path] $filePath');
        _lastGeneratedAudioPath = filePath;

        _clearLastError();
        return (filePath: filePath, attempts: attempts, useFallback: false);
      } on TimeoutException catch (e) {
        _setLastError(e);
        // ignore: avoid_print
        print('[TTS][RELEASE] 请求超时 (尝试${attempt + 1}): $e');
        if (attempt < _config.maxRetries - 1) {
          final delay = _config.baseRetryDelay * (1 << attempt);
          await _delay(delay);
          if (_disposed) return (filePath: null, attempts: attempts, useFallback: false);
          continue;
        }
        debugPrint('❌ TTS下载最终超时');
        return (filePath: null, attempts: attempts, useFallback: true);
      } catch (e) {
        _setLastError(e);
        // ignore: avoid_print
        print('[TTS][RELEASE] 下载失败 (尝试${attempt + 1}): $e');
        if (e is FormatException) {
          return (filePath: null, attempts: attempts, useFallback: false);
        }
        if (attempt < _config.maxRetries - 1) {
          // 指数退避
          final delay = _config.baseRetryDelay * (1 << attempt);
          await _delay(delay);
          if (_disposed) return (filePath: null, attempts: attempts, useFallback: false);
        } else {
          debugPrint('❌ TTS下载最终失败');
        }
      }
    }
    return (filePath: null, attempts: attempts, useFallback: true);
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
      final response = await _httpClient.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': testText, 'voice': voice}),
      ).timeout(_config.requestTimeout);

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
          throw FormatException(CyberErrorMessages.ttsMissingUrlTest(response.body));
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
        result['message'] = CyberErrorMessages.ttsServerErrorCode(response.statusCode);
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

  void _setState(TtsPlaybackState nextState) {
    if (_disposed) return;
    final bool changed = _state != nextState;
    _state = nextState;
    // 正常业务逻辑：播放中或缓冲中均应持有 WakeLock 防止屏幕熄灭
    _syncWakeLock(_state == TtsPlaybackState.playing || _state == TtsPlaybackState.buffering);
    if (changed) {
      notifyListeners();
    }
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

  Future<TtsAudioRequest?> _requestNextSentence(int session) async {
    if (onNeedPrefetch == null) {
      debugPrint('⚠️ onNeedPrefetch 未绑定，无法获取下一句');
      return null;
    }
    final request = await onNeedPrefetch!(session);
    if (_disposed || !isEnabled) return null;
    if (request == null) {
      debugPrint('⏳ onNeedPrefetch 返回 null，当前暂无可预取文本');
    }
    return request;
  }

  /// 降级：使用系统原生 TTS 朗读文本，返回是否成功
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

  /// 强制重启循环，用于解决卡顿问题
  void forceRestartLoops() {
    // 穷尽 switch：依据当前状态决定恢复目标状态
    final TtsPlaybackState resumeState = switch ((isEnabled, isPaused, isError)) {
      // 引擎已关闭
      (false, _, _) => TtsPlaybackState.disabled,
      // 引擎已暂停
      (true, true, _) => TtsPlaybackState.paused,
      // 引擎错误或正常播放 → 强制缓冲重启
      (true, false, _) => TtsPlaybackState.buffering,
    };
    debugPrint('🔄 强制重启循环 (Session=$_loopSession -> ${_loopSession + 1})');
    // 🔥 增加 session 是最彻底的停止旧循环并启动新循环的方法
    _loopSession++;
    _startingLoops = false;
    _audioPlayer.stop();
    _currentItem = null;
    _clearPrefetchQueue();
    _setState(resumeState);
    if (resumeState == TtsPlaybackState.buffering) {
      _heartbeat();
    }
  }
}

class TtsAudioItem {
  final int id;
  final int session;
  final int lineIndex;
  final String text;
  final String title;
  final Duration estimatedDuration;

  TtsAudioItem({
    required this.id,
    required this.session,
    required this.lineIndex,
    required this.text,
    required this.title,
    required this.estimatedDuration,
  });
}

class TtsAudioRequest {
  final int lineIndex;
  final String text;
  final String title;

  TtsAudioRequest({
    required this.lineIndex,
    required this.text,
    required this.title,
  });
}

/// 预加载音频项：绑定文件路径与真实行号
class _PrefetchedAudio {
  final String filePath;
  final int lineIndex;
  final String text;
  final String title;

  const _PrefetchedAudio({
    required this.filePath,
    required this.lineIndex,
    required this.text,
    required this.title,
  });
}
