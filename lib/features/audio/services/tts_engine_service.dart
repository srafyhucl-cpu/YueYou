import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../settings/providers/settings_provider.dart';
import '../../../core/config/tts_config.dart';

/// 抽象接口，用于测试时注入 Mock
abstract class TtsAudioPlayer {
  Future<void> setSource(Source source);
  Future<void> resume();
  Future<void> pause();
  Future<void> stop();
  Future<void> setVolume(double volume);
  Future<void> setPlaybackRate(double rate);
  Stream<void> get onPlayerComplete;
  Future<void> dispose();
}

/// 抽象接口，用于测试时注入 Mock
abstract class TtsWakeLock {
  Future<void> enable();
  Future<void> disable();
}

/// 抽象接口，用于测试时注入 Mock
abstract class TtsHttpClient {
  Future<http.Response> post(Uri url,
      {Map<String, String>? headers, Object? body});
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

/// 生产环境实现：包装真实 http.Client
class _RealHttpClient implements TtsHttpClient {
  @override
  Future<http.Response> post(Uri url,
      {Map<String, String>? headers, Object? body}) {
    return http.post(url, headers: headers, body: body);
  }
}

/// 阅游双轨流媒体 TTS 引擎
/// 架构：生产者/消费者双轨预加载模型
class TtsEngineService extends ChangeNotifier {
  final TtsConfig _config;

  // 核心状态
  late String _voice;
  late double _volume;
  bool _isEnabled = false;
  bool _isSpeaking = false;
  bool _isBuffering = false;
  String? _lastError;
  double _playbackRate = 1.0;
  final List<double> _speedTiers = [1.0, 1.2, 1.5, 2.0, 2.5, 0.7];

  // 双轨流媒体核心（通过接口抽象，支持测试注入）
  late final TtsAudioPlayer _audioPlayer;
  late final TtsWakeLock _wakeLock;
  late final TtsHttpClient _httpClient;
  final Future<void> Function(Duration) _delay;
  int _loopSession = 0;
  bool _wakeLockHeld = false;

  // 🔥 预加载队列：文件路径 + 真实行号绑定，彻底消灭 _currentPlayingIndex
  final List<_PrefetchedAudio> _prefetchedItems = [];

  // 循环控制
  bool _playLoopActive = false;
  bool _prefetchLoopActive = false;
  bool _startingLoops = false; // 🔥 启动锁：防止 _heartbeat 并发重复启动
  TtsAudioItem? _currentItem;

  // 空闲超时计时器
  Timer? _idleTimer;

  bool _disposed = false;
  late final Future<void> _initFuture;
  bool _initCompleted = false;

  bool get isEnabled => _isEnabled;
  bool get isPlaying => _isEnabled && _isSpeaking;
  bool get isSpeaking => _isSpeaking;
  bool get isBuffering => _isBuffering;
  String? get lastError => _lastError;
  double get playbackRate => _playbackRate;
  int get currentSession => _loopSession;
  int get bufferedCount => _prefetchedItems.length;
  TtsAudioItem? get currentItem => _currentItem;

  late SettingsProvider _settings;

  TtsEngineService(
    SettingsProvider settings, {
    TtsConfig? config,
    TtsAudioPlayer? audioPlayer,
    TtsWakeLock? wakeLock,
    TtsHttpClient? httpClient,
    Future<void> Function(Duration)? delayFn,
  })  : _config = config ?? TtsConfig.current,
        _audioPlayer = audioPlayer ?? _RealAudioPlayer(AudioPlayer()),
        _wakeLock = wakeLock ?? _RealWakeLock(),
        _httpClient = httpClient ?? _RealHttpClient(),
        _delay = delayFn ?? ((d) => Future<void>.delayed(d)) {
    _settings = settings;
    _initFuture = _initTtsHardware();
    _listenToSettings();
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
      _setLastError('设置播放倍速失败: $e');
      debugPrint('设置播放倍速失败: $e');
    }));
  }

  void _safeSetVolume(double volume) {
    unawaited(_audioPlayer.setVolume(volume).catchError((Object e) {
      _setLastError('设置音量失败: $e');
      debugPrint('设置音量失败: $e');
    }));
  }

  void _setLastError(String message) {
    if (_lastError == message) return;
    _lastError = message;
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

    if (!storyTts && _isEnabled) {
      setEnabled(false);
    } else if (storyTts && !_isEnabled) {
      setEnabled(true);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _settings.removeListener(_onSettingsChanged);
    _idleTimer?.cancel();
    _playLoopActive = false;
    _prefetchLoopActive = false;
    unawaited(_audioPlayer.dispose());
    _clearPrefetchQueue();
    super.dispose();
  }

  Future<void> _initTtsHardware() async {
    try {
      _voice = _settings.voice;
      _volume = _settings.ambientVol;
      _playbackRate = _settings.ttsRate;
      _isEnabled = _settings.storyTts;

      await _audioPlayer.setVolume(_volume.clamp(0.0, 1.0));
      await _audioPlayer.setPlaybackRate(_playbackRate);

      _initCompleted = true;
      debugPrint('🎵 双轨流媒体TTS引擎已初始化 (enabled=$_isEnabled)');
    } catch (e) {
      debugPrint('⚠️ TTS 引擎初始化失败: $e');
      _initCompleted = true;
    }
  }

  Future<void> init() async {
    // 流媒体引擎无需额外初始化
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

  Future<TtsAudioRequest?> Function(int session)? onNeedPrefetch;
  FutureOr<void> Function(TtsAudioItem item)? onItemStarted;
  FutureOr<void> Function(TtsAudioItem item)? onItemFinished;

  void play() {
    // 🔥 精准修复：直接恢复播放，不销毁队列
    if (!_isEnabled) {
      setEnabled(true);
      return;
    }
    _clearLastError();
    _audioPlayer.resume();
    if (_currentItem != null) {
      _setPlaybackFlags(isSpeaking: true, isBuffering: false);
    }
    _syncWakeLock(true);
  }

  void pause() {
    // 🔥 精准修复：直接暂停，绝不清空队列
    _audioPlayer.pause();
    _setPlaybackFlags(isSpeaking: false, isBuffering: _isBuffering);
    _syncWakeLock(false);
  }

  void setEnabled(bool enabled) {
    if (_isEnabled == enabled) return;
    _isEnabled = enabled;
    notifyListeners();
    debugPrint('🎵 TTS setEnabled: $enabled (session=$_loopSession)');
    _clearLastError();
    if (enabled) {
      // 启用时强制重启循环，确保不会跳过
      _playLoopActive = false;
      _prefetchLoopActive = false;
      _startingLoops = false;
      // 启用时启动空闲计时器
      _scheduleIdleTimer();
      if (_prefetchedItems.isEmpty) {
        _setPlaybackFlags(isSpeaking: false, isBuffering: true);
      }
      debugPrint('🚀 启动双轨循环...');
      _heartbeat();
    } else {
      // 禁用时取消空闲计时器
      _idleTimer?.cancel();
      _currentItem = null; // 🔥 关键修复：置空当前项，防止 stop 触发 onItemFinished 导致跳句
      _audioPlayer.stop();
      _setPlaybackFlags(isSpeaking: false, isBuffering: false);
    }
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

  /// 🔥 切章核心：同步递增 session，立即停播，清空队列，重启循环
  void refreshSession() {
    _loopSession++;
    debugPrint('🔄 refreshSession: session=$_loopSession');
    _audioPlayer.stop();
    _clearLastError();
    _currentItem = null;
    _setPlaybackFlags(isSpeaking: false, isBuffering: false);
    _clearPrefetchQueue();

    // 🔥 强制重置循环标志位，即使已经在运行或销毁，也要重新启动
    _playLoopActive = false;
    _prefetchLoopActive = false;
    _startingLoops = false;

    if (_isEnabled) {
      _scheduleIdleTimer();
      _heartbeat();
    }
  }

  /// 通知用户有交互行为，重置空闲计时器
  void notifyUserActivity() {
    if (!_isEnabled) return;
    _scheduleIdleTimer();
  }

  void _scheduleIdleTimer() {
    _idleTimer?.cancel();
    final int minutes = _settings.idleTimeout;
    if (minutes <= 0) return;
    _idleTimer = Timer(Duration(minutes: minutes), () {
      if (_isEnabled && !_disposed) {
        debugPrint('⏰ 空闲超时 ${minutes}min，自动暂停 TTS');
        setEnabled(false);
        _settings.setStoryTts(false);
      }
    });
  }

  void stopAll() {
    _loopSession++;
    _audioPlayer.stop();
    _currentItem = null;
    _setPlaybackFlags(isSpeaking: false, isBuffering: false);
    _clearPrefetchQueue();
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
      if (!_playLoopActive) unawaited(_startPlayLoop());
      if (!_prefetchLoopActive) unawaited(_startPrefetchLoop());
    } finally {
      _startingLoops = false;
    }
  }

  /// 生产者轨道：预加载循环
  Future<void> _startPrefetchLoop() async {
    if (_prefetchLoopActive || _disposed) {
      debugPrint('⏭️ 预加载循环已在运行或已销毁，跳过');
      return;
    }
    _prefetchLoopActive = true;
    debugPrint('🔄 预加载循环启动 (session=$_loopSession)');

    int consecutiveFailures = 0; // 🔥 连续失败计数器

    try {
      while (_prefetchLoopActive && !_disposed) {
        final int sessionSnapshot = _loopSession;

        // 队列已满或未启用，等待
        if (!_isEnabled ||
            _prefetchedItems.length >= _config.maxPrefetchQueue) {
          await _delay(const Duration(milliseconds: 500));
          continue;
        }

        // 🔥 获取下一句文本，确保顺序
        final request = await _requestNextSentence(sessionSnapshot);
        if (request == null) {
          await _delay(const Duration(milliseconds: 200));
          continue;
        }
        debugPrint('✅ 获取文本: ${request.text}');

        // 连续失败过多，暂停
        if (consecutiveFailures >= 3) {
          debugPrint('⚠️ 连续 $consecutiveFailures 次下载失败，暂停 5 秒');
          await _delay(const Duration(seconds: 5));
          consecutiveFailures = 0;
          continue;
        }

        try {
          debugPrint('⬇️ 开始下载音频: ${request.text}');
          final filePath = await _downloadTtsAudio(request, sessionSnapshot);
          if (filePath == null) {
            consecutiveFailures++;
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
            ));
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
          debugPrint(
              '⚠️ 下载失败 (${consecutiveFailures}/3): ${request.text} - $e');
          await _delay(const Duration(milliseconds: 500));
        }
      }
    } catch (e) {
      debugPrint('⚠️ 预加载循环异常: $e');
    } finally {
      _prefetchLoopActive = false;
    }
  }

  /// 消费者轨道：播放循环
  Future<void> _startPlayLoop() async {
    if (_playLoopActive || _disposed) {
      debugPrint('⏭️ 播放循环已在运行或已销毁，跳过');
      return;
    }
    _playLoopActive = true;
    debugPrint('▶️ 播放循环启动 (session=$_loopSession)');

    try {
      while (_playLoopActive && !_disposed) {
        if (!_isEnabled) {
          if (_isSpeaking || _isBuffering) {
            _setPlaybackFlags(isSpeaking: false, isBuffering: false);
          }
          await _delay(const Duration(milliseconds: 100));
          continue;
        }
        final int sessionAtStep = _loopSession;

        // 队列为空，等待缓冲
        if (_prefetchedItems.isEmpty) {
          if (!_isBuffering) {
            debugPrint('⏳ 队列为空，进入缓冲状态...');
            _setPlaybackFlags(isSpeaking: false, isBuffering: true);
          }
          await _delay(const Duration(milliseconds: 200));
          continue;
        }
        debugPrint('🎬 队列有 ${_prefetchedItems.length} 个音频，准备播放...');

        if (_isBuffering) {
          _setPlaybackFlags(isSpeaking: false, isBuffering: false);
        }

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
              ? prefetched.text.substring(
                  0, prefetched.text.length > 20 ? 20 : prefetched.text.length)
              : 'Untitled',
          estimatedDuration: const Duration(seconds: 5), // Placeholder duration
        );
        _currentItem = startItem;
        if (onItemStarted != null) {
          unawaited(Future.microtask(() => onItemStarted!(startItem)));
        }
        _setPlaybackFlags(isSpeaking: true, isBuffering: false);
        notifyListeners();

        bool naturallyFinished = false;
        try {
          final fileSize = await File(filePath).length();
          debugPrint('🔊 准备播放: $filePath (size: ${fileSize}B)');

          // 🔥 超时保护：防止 setSource 卡死
          await _audioPlayer.setSource(DeviceFileSource(filePath)).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('❌ setSource 超时，跳过此条');
              throw TimeoutException('setSource timeout');
            },
          );

          final completer = Completer<void>();
          final sub = _audioPlayer.onPlayerComplete.listen((_) {
            if (!completer.isCompleted) completer.complete();
          });

          try {
            _audioPlayer.resume();
            debugPrint('✅ AudioPlayer 已启动，倍速: $_playbackRate');

            // 🔥 播放超时保护：增加暂停感知
            // 每秒检查一次，如果处于播放状态则累积耗时，超过 30s 则超时
            int elapsedSeconds = 0;
            while (!completer.isCompleted &&
                sessionAtStep == _loopSession &&
                !_disposed) {
              if (_isEnabled && _isSpeaking) {
                elapsedSeconds++;
                if (elapsedSeconds >= 30) {
                  debugPrint('❌ 播放超时 (30s)，强制结束');
                  _audioPlayer.stop();
                  break;
                }
              } else if (!_isEnabled) {
                // 如果引擎被禁用，立即退出循环
                break;
              }
              await _delay(const Duration(seconds: 1));
            }
            naturallyFinished = completer.isCompleted &&
                sessionAtStep == _loopSession &&
                _isEnabled;
          } finally {
            await sub.cancel();
          }
        } on TimeoutException catch (e) {
          debugPrint('⚠️ 播放超时: $e');
          // 超时后继续下一条，不卡死
        } finally {
          try {
            await File(filePath).delete();
          } catch (_) {}
          // 播放结束时触发回调
          if (naturallyFinished &&
              _currentItem?.id == startItem.id &&
              onItemFinished != null) {
            unawaited(Future.microtask(() => onItemFinished!(startItem)));
          }
          _currentItem = null;
          _setPlaybackFlags(
              isSpeaking: false, isBuffering: _prefetchedItems.isNotEmpty);
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('⚠️ 播放循环异常: $e');
    } finally {
      _playLoopActive = false;
    }
  }

  /// 下载TTS音频文件（带重试机制）
  Future<String?> _downloadTtsAudio(
      TtsAudioRequest request, int session) async {
    for (int attempt = 0; attempt < _config.maxRetries; attempt++) {
      try {
        // 构建请求URL
        final uri = Uri.parse(_config.serverUrl);

        // 发送HTTP POST请求 (JSON格式以匹配服务器校验逻辑)
        final response = await _httpClient
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'text': request.text,
                'voice': _voice,
              }),
            )
            .timeout(_config.requestTimeout);

        if (response.statusCode != 200) {
          final errorBody = response.body;
          _setLastError('TTS 服务错误: HTTP ${response.statusCode}');
          debugPrint(
              '⚠️ TTS服务器返回错误: ${response.statusCode} (尝试 ${attempt + 1}/${_config.maxRetries})\n响应: $errorBody');

          // 🚨 TTS 容错：400 错误直接跳过，不重试避免死循环
          if (response.statusCode == 400) {
            debugPrint('❌ TTS 400 错误，直接跳过当前句: ${request.text}');
            return null;
          }

          if (attempt < _config.maxRetries - 1) {
            // 指数退避
            final delay = _config.baseRetryDelay * (1 << attempt);
            await _delay(delay);
            continue;
          }
          return null;
        }

        // 会话已过期
        if (session != _loopSession || _disposed) {
          return null;
        }

        // 写入临时文件
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filePath = '${tempDir.path}/tts_$timestamp.mp3';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        _clearLastError();
        return filePath;
      } catch (e) {
        _setLastError('下载TTS音频失败: $e');
        debugPrint(
            '⚠️ 下载TTS音频失败: $e (尝试 ${attempt + 1}/${_config.maxRetries})');
        if (attempt < _config.maxRetries - 1) {
          // 指数退避
          final delay = _config.baseRetryDelay * (1 << attempt);
          await _delay(delay);
        } else {
          debugPrint('❌ TTS下载最终失败');
        }
      }
    }
    return null;
  }

  /// 🛠️ TTS 连接测试工具
  /// 返回详细的诊断信息，帮助排查问题
  Future<Map<String, dynamic>> testConnection() async {
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
        body: {'text': testText, 'voice': _voice},
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('请求超时 (10秒)');
        },
      );

      result['statusCode'] = response.statusCode;
      result['responseSize'] = response.bodyBytes.length;

      if (response.statusCode == 200) {
        result['steps'].add({
          'step': 3,
          'name': 'HTTP 请求',
          'status': 'success',
          'message':
              '状态码: ${response.statusCode}, 响应大小: ${response.bodyBytes.length} 字节',
        });

        // 步骤 4：验证音频文件
        if (response.bodyBytes.length < 1024) {
          result['steps'].add({
            'step': 4,
            'name': '验证音频文件',
            'status': 'warning',
            'message': '警告：音频文件太小 (<1KB)，可能是错误响应',
          });
        } else {
          result['steps'].add({
            'step': 4,
            'name': '验证音频文件',
            'status': 'success',
            'message': '音频文件大小正常: ${response.bodyBytes.length} 字节',
          });
        }

        // 步骤 5：尝试写入文件
        try {
          final tempDir = await getTemporaryDirectory();
          final testFile = File('${tempDir.path}/tts_test.mp3');
          await testFile.writeAsBytes(response.bodyBytes);

          result['steps'].add({
            'step': 5,
            'name': '写入文件',
            'status': 'success',
            'message': '成功写入: ${testFile.path}',
          });

          // 清理测试文件
          await testFile.delete();
        } catch (e) {
          result['steps'].add({
            'step': 5,
            'name': '写入文件',
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
        result['message'] = '服务器返回错误: ${response.statusCode}';
        _setLastError('连接测试失败: HTTP ${response.statusCode}');
      }
    } on TimeoutException catch (e) {
      result['steps'].add({
        'step': 3,
        'name': 'HTTP 请求',
        'status': 'error',
        'message': '请求超时: $e',
      });
      result['message'] = '请求超时，请检查网络连接或服务器状态';
      _setLastError('连接测试超时: $e');
    } on SocketException catch (e) {
      result['steps'].add({
        'step': 3,
        'name': 'HTTP 请求',
        'status': 'error',
        'message': '网络错误: $e',
      });
      result['message'] = '无法连接到服务器，请检查：\n1. 服务器是否启动\n2. 防火墙设置\n3. 网络连接';
      _setLastError('连接测试网络异常: $e');
    } catch (e) {
      result['steps'].add({
        'step': 3,
        'name': 'HTTP 请求',
        'status': 'error',
        'message': '未知错误: $e',
      });
      result['message'] = '测试失败: $e';
      _setLastError('连接测试失败: $e');
    }

    return result;
  }

  void _setPlaybackFlags(
      {required bool isSpeaking, required bool isBuffering}) {
    final bool changed =
        _isSpeaking != isSpeaking || _isBuffering != isBuffering;
    _isSpeaking = isSpeaking;
    _isBuffering = isBuffering;
    _syncWakeLock(_isEnabled && _isSpeaking);
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
    if (onNeedPrefetch == null) return null;
    return onNeedPrefetch!(session);
  }

  /// 强制重启循环，用于解决卡顿问题
  void forceRestartLoops() {
    debugPrint('🔄 强制重启循环 (Session=$_loopSession -> ${_loopSession + 1})');
    // 🔥 增加 session 是最彻底的停止旧循环并启动新循环的方法
    _loopSession++;
    _playLoopActive = false;
    _prefetchLoopActive = false;
    _startingLoops = false;
    _audioPlayer.stop();
    _setPlaybackFlags(
        isSpeaking: false, isBuffering: _prefetchedItems.isNotEmpty);
    _heartbeat();
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
