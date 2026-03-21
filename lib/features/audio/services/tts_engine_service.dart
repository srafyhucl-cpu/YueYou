import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../settings/providers/settings_provider.dart';

/// 阅游双轨流媒体 TTS 引擎
/// 架构：生产者/消费者双轨预加载模型
/// 服务器：http://8.218.177.149:3000/api/v1/tts/createStream
class TtsEngineService extends ChangeNotifier {
  static const String _ttsServerUrl =
      'http://8.218.177.149:3000/api/v1/tts/createStream';

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
  final List<String> _prefetchQueue = []; // 本地临时MP3文件路径队列
  int _loopSession = 0; // 会话锁
  bool _wakeLockHeld = false;

  // 兼容层
  bool _playLoopActive = false;
  bool _prefetchLoopActive = false;
  TtsAudioItem? _currentItem;
  final Queue<TtsAudioItem> _audioBufferQueue = Queue<TtsAudioItem>();
  int _currentPlayingIndex = 0; // 当前播放的句子索引

  bool get isEnabled => _isEnabled;
  bool get isPlaying => _isEnabled;
  bool get isSpeaking => _isSpeaking;
  bool get isBuffering => _isBuffering;
  double get playbackRate => _playbackRate;
  int get currentSession => _loopSession;
  int get bufferedCount => _prefetchQueue.length;
  TtsAudioItem? get currentItem => _currentItem;

  late SettingsProvider _settings;

  TtsEngineService(SettingsProvider settings) {
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
    _settings.removeListener(_onSettingsChanged);
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
    setEnabled(true);
  }

  void pause() {
    setEnabled(false);
  }

  void setEnabled(bool enable) {
    if (_isEnabled == enable) return;
    _isEnabled = enable;
    _syncWakeLock(_isEnabled && _isSpeaking);
    if (enable) {
      if (_prefetchQueue.isEmpty) {
        _setPlaybackFlags(isSpeaking: false, isBuffering: true);
      }
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

  void refreshSession() {
    _loopSession++;
    _audioPlayer.stop();
    _audioBufferQueue.clear();
    _currentItem = null;
    _currentPlayingIndex = 0;
    _setPlaybackFlags(isSpeaking: false, isBuffering: false);
    // 关键修复：异步清理文件，不阻塞主线程
    _clearPrefetchQueue();
    _heartbeat();
  }

  void stopAll() {
    _loopSession++;
    _audioPlayer.stop();
    _audioBufferQueue.clear();
    _currentItem = null;
    _currentPlayingIndex = 0;
    _setPlaybackFlags(isSpeaking: false, isBuffering: false);
    // 异步清理文件
    _clearPrefetchQueue();
  }

  /// 清空预加载队列并异步删除临时文件（不阻塞主线程）
  void _clearPrefetchQueue() {
    final filesToDelete = List<String>.from(_prefetchQueue);
    _prefetchQueue.clear();

    // 异步删除文件，不阻塞主线程
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
    _startPlayLoop();
    _startPrefetchLoop();
  }

  /// 生产者轨道：预加载循环
  Future<void> _startPrefetchLoop() async {
    if (_prefetchLoopActive) return;
    _prefetchLoopActive = true;

    while (true) {
      final int sessionSnapshot = _loopSession;

      // 队列已满或未启用，等待
      if (!_isEnabled || _prefetchQueue.length >= 3) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        continue;
      }

      // 请求下一句文本
      final TtsAudioRequest? request =
          await _requestNextSentence(sessionSnapshot);
      if (request == null) {
        await Future<void>.delayed(const Duration(seconds: 1));
        continue;
      }

      if (request.text.trim().isEmpty) {
        continue;
      }

      // 会话已过期，放弃
      if (sessionSnapshot != _loopSession) {
        continue;
      }

      // 下载音频文件
      final String? filePath =
          await _downloadTtsAudio(request, sessionSnapshot);
      if (filePath != null && sessionSnapshot == _loopSession) {
        _prefetchQueue.add(filePath);
        final preview = request.text.length > 10
            ? '${request.text.substring(0, 10)}...'
            : request.text;
        debugPrint('✅ 预加载完成: $preview -> $filePath');
        notifyListeners();
      }
    }
  }

  /// 消费者轨道：播放循环
  Future<void> _startPlayLoop() async {
    if (_playLoopActive) return;
    _playLoopActive = true;

    while (true) {
      if (!_isEnabled) {
        if (_isSpeaking || _isBuffering) {
          _setPlaybackFlags(isSpeaking: false, isBuffering: false);
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }

      final int sessionAtStep = _loopSession;

      // 队列为空，等待缓冲
      if (_prefetchQueue.isEmpty) {
        if (!_isBuffering) {
          _setPlaybackFlags(isSpeaking: false, isBuffering: true);
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }

      if (_isBuffering) {
        _setPlaybackFlags(isSpeaking: false, isBuffering: false);
      }

      // 弹出文件路径
      final String filePath = _prefetchQueue.removeAt(0);

      // 会话已过期，删除文件
      if (sessionAtStep != _loopSession) {
        try {
          await File(filePath).delete();
        } catch (_) {}
        continue;
      }

      // 触发 onItemStarted 回调
      if (onItemStarted != null) {
        final item = TtsAudioItem(
          id: DateTime.now().microsecondsSinceEpoch,
          session: sessionAtStep,
          lineIndex: _currentPlayingIndex,
          text: '',
          title: '',
          estimatedDuration: Duration.zero,
        );
        _currentItem = item;
        await onItemStarted!(item);
      }

      // 播放音频
      _setPlaybackFlags(isSpeaking: true, isBuffering: false);

      try {
        // 使用 Completer 等待播放完成
        final completer = Completer<void>();

        // 监听播放完成
        late StreamSubscription subscription;
        subscription = _audioPlayer.onPlayerComplete.listen((_) {
          if (!completer.isCompleted) {
            completer.complete();
          }
          subscription.cancel();
        });

        // 关键修复：先stop再播放，避免资源注入冲突
        await _audioPlayer.stop();
        await _audioPlayer.play(DeviceFileSource(filePath));

        // 等待播放完成或会话过期
        await Future.any([
          completer.future,
          Future.delayed(const Duration(seconds: 30)),
        ]);

        subscription.cancel();

        // 删除已播放的临时文件
        try {
          await File(filePath).delete();
        } catch (e) {
          debugPrint('⚠️ 删除已播放文件失败: $e');
        }

        // 触发 onItemFinished 回调
        if (onItemFinished != null && sessionAtStep == _loopSession) {
          final item = TtsAudioItem(
            id: DateTime.now().microsecondsSinceEpoch,
            session: sessionAtStep,
            lineIndex: _currentPlayingIndex,
            text: '',
            title: '',
            estimatedDuration: Duration.zero,
          );
          await onItemFinished!(item);
          _currentPlayingIndex++; // 移动到下一句
        }

        _currentItem = null;

        _setPlaybackFlags(
            isSpeaking: false, isBuffering: _prefetchQueue.isEmpty);
      } catch (e) {
        debugPrint('⚠️ 播放失败: $e');
        _setPlaybackFlags(isSpeaking: false, isBuffering: false);

        // 删除失败的文件
        try {
          await File(filePath).delete();
        } catch (_) {}
      }
    }
  }

  /// 下载TTS音频文件
  Future<String?> _downloadTtsAudio(
      TtsAudioRequest request, int session) async {
    try {
      // 构建请求URL
      final uri = Uri.parse(_ttsServerUrl);

      // 发送HTTP POST请求（与旧代码保持一致）
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'text': request.text,
              'voice': _voice,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('⚠️ TTS服务器返回错误: ${response.statusCode}');
        return null;
      }

      // 会话已过期
      if (session != _loopSession) {
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
      debugPrint('⚠️ 下载TTS音频失败: $e');
      return null;
    }
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
