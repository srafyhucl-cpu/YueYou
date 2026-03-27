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
  double _playbackRate = 1.0;
  final List<double> _speedTiers = [1.0, 1.2, 1.5, 2.0, 2.5, 0.7];

  // 双轨流媒体核心
  final AudioPlayer _audioPlayer = AudioPlayer();
  int _loopSession = 0; // 会话锁 — 切章时同步递增
  bool _wakeLockHeld = false;

  // 🔥 预加载队列：文件路径 + 真实行号绑定，彻底消灭 _currentPlayingIndex
  final List<_PrefetchedAudio> _prefetchedItems = [];

  // 循环控制
  bool _playLoopActive = false;
  bool _prefetchLoopActive = false;
  bool _startingLoops = false; // 🔥 启动锁：防止 _heartbeat 并发重复启动
  TtsAudioItem? _currentItem;

  bool _disposed = false;

  bool get isEnabled => _isEnabled;
  bool get isPlaying => _isEnabled && _isSpeaking;
  bool get isSpeaking => _isSpeaking;
  bool get isBuffering => _isBuffering;
  double get playbackRate => _playbackRate;
  int get currentSession => _loopSession;
  int get bufferedCount => _prefetchedItems.length;
  TtsAudioItem? get currentItem => _currentItem;

  late SettingsProvider _settings;

  TtsEngineService(SettingsProvider settings, {TtsConfig? config})
      : _config = config ?? TtsConfig.current {
    _settings = settings;
    _initTtsHardware();
    _listenToSettings();
  }

  void _listenToSettings() {
    _settings.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    _syncSettingsInternal(
      storyTts: _settings.storyTts,
      ttsRate: _settings.ttsRate,
      voice: _settings.voice,
      volume: _settings.ambientVol,
    );
  }

  void _syncSettingsInternal({
    required bool storyTts,
    required double ttsRate,
    required String voice,
    required double volume,
  }) {
    if (_playbackRate != ttsRate) {
      _playbackRate = ttsRate;
      _audioPlayer.setPlaybackRate(ttsRate);
    }

    if (_volume != volume) {
      _volume = volume.clamp(0.0, 1.0);
      _audioPlayer.setVolume(_volume);
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
    _playLoopActive = false;
    _prefetchLoopActive = false;
    _audioPlayer.dispose();
    _clearPrefetchQueue();
    super.dispose();
  }

  Future<void> _initTtsHardware() async {
    _voice = _settings.voice;
    _volume = _settings.ambientVol;
    _playbackRate = _settings.ttsRate;

    await _audioPlayer.setVolume(_volume.clamp(0.0, 1.0));
    await _audioPlayer.setPlaybackRate(_playbackRate);

    debugPrint('🎵 双轨流媒体TTS引擎已初始化');
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
      _isEnabled = true;
      notifyListeners();
    }
    _audioPlayer.resume();
    _syncWakeLock(true);
  }

  void pause() {
    // 🔥 精准修复：直接暂停，绝不清空队列
    _audioPlayer.pause();
    _syncWakeLock(false);
  }

  void setEnabled(bool enable) {
    if (_isEnabled == enable) return;
    _isEnabled = enable;
    debugPrint('🎵 TTS setEnabled: $enable (session=$_loopSession)');
    _syncWakeLock(_isEnabled && _isSpeaking);
    if (enable) {
      if (_prefetchedItems.isEmpty) {
        _setPlaybackFlags(isSpeaking: false, isBuffering: true);
      }
      debugPrint('🚀 启动双轨循环...');
      _heartbeat();
      return;
    }
    _audioPlayer.stop();
    _setPlaybackFlags(isSpeaking: false, isBuffering: false);
  }

  @Deprecated('Use internal listener instead')
  void applySettings({
    required bool storyTts,
    required double ttsRate,
    required String voice,
    required double volume,
  }) {
    // 空实现，保留接口兼容性
  }

  void cycleSpeed() {
    final int currentIndex = _speedTiers.indexOf(_playbackRate);
    final int nextIndex = (currentIndex + 1) % _speedTiers.length;
    _playbackRate = _speedTiers[nextIndex];
    _audioPlayer.setPlaybackRate(_playbackRate);
    notifyListeners();
  }

  void syncSpeedFromSettings(double logicalRate, double hardwareRate) {
    if (_playbackRate == logicalRate) return;
    _playbackRate = logicalRate;
    _audioPlayer.setPlaybackRate(logicalRate);
    notifyListeners();
  }

  void syncVolumeFromSettings(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    _audioPlayer.setVolume(_volume);
  }

  void syncVoiceFromSettings(String voice) {
    if (_voice == voice) return;
    _voice = voice;
    refreshSession();
  }

  /// 🔥 切章核心：同步递增 session，立即停播，清空队列，重启循环
  void refreshSession() {
    _loopSession++;
    debugPrint('🔄 refreshSession: session=$_loopSession');
    _audioPlayer.stop();
    _currentItem = null;
    _setPlaybackFlags(isSpeaking: false, isBuffering: false);
    _clearPrefetchQueue();

    // 🔥 重置循环标志位，允许重新启动
    _playLoopActive = false;
    _prefetchLoopActive = false;

    if (_isEnabled) {
      _heartbeat();
    }
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
    if (_startingLoops) return;
    _startingLoops = true;

    _startPlayLoop();
    _startPrefetchLoop();

    _startingLoops = false;
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
          await Future<void>.delayed(const Duration(milliseconds: 500));
          continue;
        }

        // 请求下一句文本
        debugPrint('📡 请求下一句文本 (session=$sessionSnapshot)...');
        final TtsAudioRequest? request =
            await _requestNextSentence(sessionSnapshot);
        if (request == null) {
          debugPrint('⚠️ onNeedPrefetch 返回 null，等待1秒...');
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }
        final textPreview = request.text.length > 20
            ? '${request.text.substring(0, 20)}...'
            : request.text;
        debugPrint('✅ 获取文本: $textPreview');

        // 🔥 会话锁检查：异步等待后必须重新验证
        if (sessionSnapshot != _loopSession || _disposed) {
          continue;
        }

        // TTS 容错：拦截空字符串和短句（API要求至少5字符）
        final trimmedText = request.text.trim();
        if (trimmedText.isEmpty || trimmedText.length < 5) {
          debugPrint('⚠️ 文本太短 (<5字符)，跳过: $trimmedText');
          continue;
        }

        // 下载音频文件
        final downloadPreview = request.text.length > 10
            ? '${request.text.substring(0, 10)}...'
            : request.text;
        debugPrint('⬇️ 开始下载音频: $downloadPreview');
        final String? filePath =
            await _downloadTtsAudio(request, sessionSnapshot);
        if (filePath == null) {
          consecutiveFailures++;
          debugPrint('❌ 音频下载失败 (连续失败: $consecutiveFailures)');

          // 🔥 连续失败5次 → 服务器任务队列已满，暂停15秒让所有任务过期
          if (consecutiveFailures >= 5) {
            debugPrint('🚨 服务器任务队列已满，暂停预加载15秒...');
            consecutiveFailures = 0;
            await Future<void>.delayed(const Duration(seconds: 15));
            debugPrint('⏰ 等待完成，重新尝试...');
            continue; // 不跳过，等待后重试同一句
          }

          // 🔥 失败后等待3秒再重试（让服务器任务队列释放）
          await Future<void>.delayed(const Duration(seconds: 3));
          continue; // 重试同一句
        }

        // 🔥 成功后重置失败计数器
        consecutiveFailures = 0;

        // 🔥 下载完成后再次检查会话锁
        if (sessionSnapshot == _loopSession && !_disposed) {
          _prefetchedItems.add(_PrefetchedAudio(
            filePath: filePath,
            lineIndex: request.lineIndex,
            text: request.text,
            title: request.title,
          ));
          final preview = request.text.length > 10
              ? '${request.text.substring(0, 10)}...'
              : request.text;
          debugPrint('✅ 预加载完成: $preview -> $filePath');
          notifyListeners();
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
          await Future<void>.delayed(const Duration(milliseconds: 100));
          continue;
        }

        final int sessionAtStep = _loopSession;

        // 队列为空，等待缓冲
        if (_prefetchedItems.isEmpty) {
          if (!_isBuffering) {
            debugPrint('⏳ 队列为空，进入缓冲状态...');
            _setPlaybackFlags(isSpeaking: false, isBuffering: true);
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
          continue;
        }
        debugPrint('🎬 队列有 ${_prefetchedItems.length} 个音频，准备播放...');

        if (_isBuffering) {
          _setPlaybackFlags(isSpeaking: false, isBuffering: false);
        }

        // 🔥 弹出队列头部，携带真实 lineIndex
        final _PrefetchedAudio prefetched = _prefetchedItems.removeAt(0);
        final String filePath = prefetched.filePath;
        final int realLineIndex = prefetched.lineIndex;

        // 会话已过期，删除文件
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
          title: prefetched.title,
          estimatedDuration: Duration.zero,
        );
        _currentItem = startItem;
        if (onItemStarted != null) {
          await onItemStarted!(startItem);
        }

        // 🔥 播放音频（优化：setSource预热）
        _setPlaybackFlags(isSpeaking: true, isBuffering: false);

        try {
          // 🔥 文件存在性检查：防止文件未完全写入
          final file = File(filePath);
          if (!await file.exists()) {
            debugPrint('❌ 音频文件不存在: $filePath');
            continue; // 跳过此条，继续下一条
          }

          // 🔥 文件大小检查：防止空文件或损坏文件
          final fileSize = await file.length();
          if (fileSize < 1024) {
            debugPrint('❌ 音频文件太小 (<1KB): $filePath, size: $fileSize');
            try {
              await file.delete();
            } catch (_) {}
            continue;
          }

          final completer = Completer<void>();
          late StreamSubscription completeSubscription;

          completeSubscription = _audioPlayer.onPlayerComplete.listen((_) {
            if (!completer.isCompleted) completer.complete();
          });

          try {
            debugPrint('🔊 准备播放: $filePath (size: ${fileSize}B)');

            // 🔥 超时保护：防止 setSource 卡死
            await _audioPlayer.setSource(DeviceFileSource(filePath)).timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                debugPrint('❌ setSource 超时，跳过此条');
                throw TimeoutException('setSource timeout');
              },
            );

            await _audioPlayer.resume(); // resume 比 play 快几十毫秒

            // 🔥 延迟50ms重新同步倍速，确保生效（某些安卓机型需要）
            await Future.delayed(const Duration(milliseconds: 50));
            await _audioPlayer.setPlaybackRate(_playbackRate);

            debugPrint('✅ AudioPlayer 已启动，倍速: $_playbackRate');

            // 🔥 播放超时保护：防止无限等待
            await completer.future.timeout(
              const Duration(seconds: 30),
              onTimeout: () {
                debugPrint('❌ 播放超时，强制结束');
              },
            );
          } on TimeoutException catch (e) {
            debugPrint('⚠️ 播放超时: $e');
            // 超时后继续下一条，不卡死
          } finally {
            await completeSubscription.cancel();
          }

          // 删除已播放文件
          try {
            await File(filePath).delete();
          } catch (_) {}

          // 🔥 触发 onItemFinished 回调，携带真实行号
          if (onItemFinished != null &&
              sessionAtStep == _loopSession &&
              !_disposed) {
            final finishItem = TtsAudioItem(
              id: DateTime.now().microsecondsSinceEpoch,
              session: sessionAtStep,
              lineIndex: realLineIndex,
              text: prefetched.text,
              title: prefetched.title,
              estimatedDuration: Duration.zero,
            );
            await onItemFinished!(finishItem);
          }

          _currentItem = null;
          _setPlaybackFlags(
              isSpeaking: false, isBuffering: _prefetchedItems.isEmpty);
        } catch (e, stackTrace) {
          debugPrint('❌ AudioPlayer 异常: $e');
          debugPrint('❌ StackTrace: $stackTrace');

          // 🔥 尝试重置 AudioPlayer，防止状态异常
          try {
            await _audioPlayer.stop();
            await Future.delayed(const Duration(milliseconds: 100));
          } catch (_) {}

          _setPlaybackFlags(isSpeaking: false, isBuffering: false);
          try {
            await File(filePath).delete();
          } catch (_) {}
          // 播放失败不中断整个循环，继续下一条
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

        // 发送HTTP POST请求
        final response = await http
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
            await Future.delayed(delay);
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

        return filePath;
      } catch (e) {
        debugPrint(
            '⚠️ 下载TTS音频失败: $e (尝试 ${attempt + 1}/${_config.maxRetries})');
        if (attempt < _config.maxRetries - 1) {
          // 指数退避
          final delay = _config.baseRetryDelay * (1 << attempt);
          await Future.delayed(delay);
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

      // 步骤 2：发送测试请求
      final uri = Uri.parse(_config.serverUrl);
      result['steps'].add({
        'step': 2,
        'name': '解析 URL',
        'status': 'success',
        'message': 'Host: ${uri.host}, Port: ${uri.port}, Path: ${uri.path}',
      });

      // 步骤 3：发送 HTTP 请求
      final testText = '测试文本一二三四五';
      debugPrint('📡 发送 TTS 测试请求: $testText');

      final response = await http
          .post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'text': testText,
          'voice': _voice,
        }),
      )
          .timeout(
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
      } else {
        result['steps'].add({
          'step': 3,
          'name': 'HTTP 请求',
          'status': 'error',
          'message': '服务器返回错误: ${response.statusCode}\n响应: ${response.body}',
        });
        result['message'] = '服务器返回错误: ${response.statusCode}';
      }
    } on TimeoutException catch (e) {
      result['steps'].add({
        'step': 3,
        'name': 'HTTP 请求',
        'status': 'error',
        'message': '请求超时: $e',
      });
      result['message'] = '请求超时，请检查网络连接或服务器状态';
    } on SocketException catch (e) {
      result['steps'].add({
        'step': 3,
        'name': 'HTTP 请求',
        'status': 'error',
        'message': '网络错误: $e',
      });
      result['message'] = '无法连接到服务器，请检查：\n1. 服务器是否启动\n2. 防火墙设置\n3. 网络连接';
    } catch (e) {
      result['steps'].add({
        'step': 3,
        'name': 'HTTP 请求',
        'status': 'error',
        'message': '未知错误: $e',
      });
      result['message'] = '测试失败: $e';
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
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {}
  }

  Future<TtsAudioRequest?> _requestNextSentence(int session) async {
    if (onNeedPrefetch == null) return null;
    return onNeedPrefetch!(session);
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
