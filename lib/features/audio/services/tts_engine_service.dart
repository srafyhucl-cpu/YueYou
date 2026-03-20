import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../settings/providers/settings_provider.dart';

/// 阅游全息 TTS 发声引擎
/// 职责：管理 TTS 预加载队列、播控状态机、多倍速循环逻辑
/// 1:1 复刻老代码中的 startPrefetchLoop 与 startPlayLoop 状态机架构
class TtsEngineService extends ChangeNotifier {
  late String _voice;
  late double _volume;
  bool _isEnabled = false;
  bool _isSpeaking = false;
  bool _isBuffering = false;
  String? _currentSpeakingText;
  List<Map<String, String>> _availableVoices = [];
  double _playbackRate = 1.0;
  final List<double> _speedTiers = [1.0, 1.2, 1.5, 2.0, 2.5, 0.7];
  final Queue<TtsAudioItem> _audioBufferQueue = Queue<TtsAudioItem>();
  int _currentSession = 1;
  bool _playLoopActive = false;
  bool _prefetchLoopActive = false;
  TtsAudioItem? _currentItem;
  Completer<void>? _playInterruptCompleter;
  bool _wakeLockHeld = false;

  bool get isEnabled => _isEnabled;
  bool get isPlaying => _isEnabled;
  bool get isSpeaking => _isSpeaking;
  bool get isBuffering => _isBuffering;
  double get playbackRate => _playbackRate;
  int get currentSession => _currentSession;
  int get bufferedCount => _audioBufferQueue.length;
  TtsAudioItem? get currentItem => _currentItem;

  // 2. 新增一个底层的 TTS 实例
  late FlutterTts _flutterTts;

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
    // 纯净的设置同步，不触发notifyListeners
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
    // 同步语速（不触发notifyListeners）
    if (_playbackRate != ttsRate) {
      _playbackRate = ttsRate;
      if (!_isSpeaking) {
        double hardwareRate = 0.5 * (ttsRate / 1.0);
        _flutterTts.setSpeechRate(hardwareRate.clamp(0.1, 1.0));
      }
    }

    // 同步音量
    if (_volume != volume) {
      _volume = volume.clamp(0.0, 1.0);
      _flutterTts.setVolume(_volume);
    }

    // 同步音色
    if (_voice != voice) {
      _voice = voice;
      _applyVoiceSetting(voice);
    }

    // 同步TTS开关
    if (!storyTts && _isEnabled) {
      setEnabled(false);
    } else if (storyTts && !_isEnabled) {
      setEnabled(true);
    }
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  Future<void> _initTtsHardware() async {
    _flutterTts = FlutterTts();
    await _flutterTts.setLanguage("zh-CN");
    await _flutterTts.awaitSpeakCompletion(true);

    // 从settings初始化
    _voice = _settings.voice;
    _volume = _settings.ambientVol;
    _playbackRate = _settings.ttsRate;

    // 音质调优：设置 pitch 为 1.05 提升听感
    await _flutterTts.setPitch(1.05);
    _flutterTts.setVolume(_volume.clamp(0.0, 1.0));
    double hardwareRate = 0.5 * (_playbackRate / 1.0);
    _flutterTts.setSpeechRate(hardwareRate.clamp(0.1, 1.0));

    init();
  }

  Future<void> init() async {
    _flutterTts.setCompletionHandler(() {
      // Completion handled by awaitSpeakCompletion
    });
    _flutterTts.setErrorHandler((msg) {
      debugPrint('🔴 TTS Error: $msg');
    });

    // 获取系统可用音色列表
    try {
      final voices = await _flutterTts.getVoices;
      if (voices is List) {
        _availableVoices = voices
            .cast<Map<dynamic, dynamic>>()
            .map((v) {
              return {
                'name': v['name']?.toString() ?? '',
                'locale': v['locale']?.toString() ?? '',
              };
            })
            .where((v) => v['locale']?.contains('zh') ?? false)
            .toList();
        debugPrint('🎵 可用中文音色: ${_availableVoices.length} 个');
      }
    } catch (e) {
      debugPrint('⚠️ 获取音色列表失败: $e');
    }
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
    if (_isEnabled == enable) {
      return;
    }
    _isEnabled = enable;
    _syncWakeLock(_isEnabled && _isSpeaking);
    if (enable) {
      if (_audioBufferQueue.isEmpty) {
        _setPlaybackFlags(isSpeaking: false, isBuffering: true);
      }
      _heartbeat();
      return;
    }
    _stopCurrentPlayback(requeueCurrent: true);
    _setPlaybackFlags(isSpeaking: false, isBuffering: false);
  }

  /// 已废弃：改为内部监听SettingsProvider
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

    // 无缝变速：不打断当前句子，从下一句自然生效
    if (!_isSpeaking) {
      double hardwareRate = 0.5 * (_playbackRate / 1.0);
      _flutterTts.setSpeechRate(hardwareRate.clamp(0.1, 1.0));
    }

    notifyListeners();
  }

  /// 从设置页直接同步倍速（对应 JS updateSetting('voice'/'ttsRate') 调用链）
  void syncSpeedFromSettings(double logicalRate, double hardwareRate) {
    if (_playbackRate == logicalRate) return;
    _playbackRate = logicalRate;

    // 实时生效：如果正在播报，立即stop+重播
    final needReplay = _isSpeaking && _currentSpeakingText != null;
    final textToReplay = _currentSpeakingText;

    // 应用新语速
    _flutterTts.setSpeechRate(hardwareRate.clamp(0.1, 1.0));

    // 重播当前句子
    if (needReplay && textToReplay != null) {
      _flutterTts.stop().then((_) {
        _flutterTts.speak(textToReplay);
      });
    }

    notifyListeners();
  }

  void syncVolumeFromSettings(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    _flutterTts.setVolume(_volume);
  }

  void syncVoiceFromSettings(String voice) {
    if (_voice == voice) return;
    _voice = voice;

    // 实时生效：如果正在播报，立即stop+重播
    final needReplay = _isSpeaking && _currentSpeakingText != null;
    final textToReplay = _currentSpeakingText;

    // 应用新音色
    _applyVoiceSetting(voice);

    // 重播当前句子
    if (needReplay && textToReplay != null) {
      _flutterTts.stop().then((_) {
        _flutterTts.speak(textToReplay);
      });
    }
  }

  void _applyVoiceSetting(String voice) {
    // 尝试从可用音色列表中匹配
    final matchedVoice = _availableVoices.firstWhere(
      (v) => v['name'] == voice,
      orElse: () => _availableVoices.isNotEmpty ? _availableVoices.first : {},
    );

    if (matchedVoice.isNotEmpty &&
        matchedVoice['name'] != null &&
        matchedVoice['locale'] != null) {
      // 传入完整的Map参数，包含name和locale
      _flutterTts.setVoice({
        'name': matchedVoice['name']!,
        'locale': matchedVoice['locale']!,
      }).catchError((e) {
        debugPrint('⚠️ setVoice失败: $e，回退到setLanguage');
        _flutterTts.setLanguage('zh-CN');
      });
    } else {
      debugPrint('⚠️ 未找到匹配音色，使用默认语言');
      _flutterTts.setLanguage('zh-CN');
    }
  }

  void refreshSession() {
    _currentSession++;
    _stopCurrentPlayback(requeueCurrent: false);
    _audioBufferQueue.clear();
    _currentItem = null;
    _setPlaybackFlags(isSpeaking: false, isBuffering: false);
    _heartbeat();
  }

  void stopAll() {
    _currentSession++;
    _stopCurrentPlayback(requeueCurrent: false);
    _audioBufferQueue.clear();
    _currentItem = null;
    _setPlaybackFlags(isSpeaking: false, isBuffering: false);
  }

  void _heartbeat() {
    _startPlayLoop();
    _startPrefetchLoop();
  }

  Future<void> _startPrefetchLoop() async {
    if (_prefetchLoopActive) {
      return;
    }
    _prefetchLoopActive = true;
    while (true) {
      final int sessionSnapshot = _currentSession;
      if (!_isEnabled || _audioBufferQueue.length >= 6) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        continue;
      }
      final TtsAudioRequest? request =
          await _requestNextSentence(sessionSnapshot);
      if (request == null) {
        await Future<void>.delayed(const Duration(seconds: 1));
        continue;
      }
      if (request.text.trim().isEmpty) {
        continue;
      }
      final TtsAudioItem? item = await _fetchTtsAsset(request, sessionSnapshot);
      if (sessionSnapshot != _currentSession) {
        continue;
      }
      if (item != null) {
        _audioBufferQueue.add(item);
        notifyListeners();
      }
    }
  }

  Future<void> _startPlayLoop() async {
    if (_playLoopActive) {
      return;
    }
    _playLoopActive = true;
    while (true) {
      if (!_isEnabled) {
        if (_isSpeaking || _isBuffering) {
          _setPlaybackFlags(isSpeaking: false, isBuffering: false);
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }
      final int sessionAtStep = _currentSession;
      if (_audioBufferQueue.isEmpty) {
        if (!_isBuffering) {
          _setPlaybackFlags(isSpeaking: _isSpeaking, isBuffering: true);
        }
        if (_isSpeaking) {
          _setPlaybackFlags(isSpeaking: false, isBuffering: true);
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }
      if (_isBuffering) {
        _setPlaybackFlags(isSpeaking: _isSpeaking, isBuffering: false);
      }
      final TtsAudioItem item = _audioBufferQueue.removeFirst();
      if (item.session != _currentSession) {
        continue;
      }
      _stopCurrentPlayback(requeueCurrent: false);
      _currentItem = item;
      _setPlaybackFlags(isSpeaking: true, isBuffering: false);
      if (onItemStarted != null) {
        await onItemStarted!(item);
      }
      bool finished = false;
      _playInterruptCompleter = Completer<void>();
      await Future.any<void>([
        _executePhysicalPlay(item, sessionAtStep).then((_) {
          finished = true;
        }),
        _playInterruptCompleter!.future,
        Future<void>.delayed(const Duration(seconds: 40)),
      ]);
      _playInterruptCompleter = null;
      if (!finished && !_isEnabled && _currentSession == sessionAtStep) {
        _audioBufferQueue.addFirst(item);
        _currentItem = null;
        continue;
      }
      if (_currentSession == sessionAtStep && finished) {
        if (onItemFinished != null) {
          await onItemFinished!(item);
        }
      }
      _currentItem = null;
      if (_currentSession == sessionAtStep && _isEnabled) {
        _setPlaybackFlags(
            isSpeaking: false, isBuffering: _audioBufferQueue.isEmpty);
      }
    }
  }

  void _stopCurrentPlayback({required bool requeueCurrent}) {
    _playInterruptCompleter?.complete();
    _playInterruptCompleter = null;

    // 硬件级物理闭嘴！
    _flutterTts.stop();

    if (requeueCurrent && _currentItem != null) {
      _audioBufferQueue.addFirst(_currentItem!);
    }
    _currentItem = null;
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

  Future<TtsAudioItem?> _fetchTtsAsset(
      TtsAudioRequest request, int session) async {
    final String safeText = request.text.trim().length < 5
        ? request.text.trim().padRight(5, '。')
        : request.text.trim();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (session != _currentSession) {
      return null;
    }
    return TtsAudioItem(
      id: DateTime.now().microsecondsSinceEpoch,
      session: session,
      lineIndex: request.lineIndex,
      text: safeText,
      title: request.title,
      estimatedDuration: Duration(
        milliseconds:
            ((safeText.length / (4.5 * _playbackRate)) * 1000).round(),
      ),
    );
  }

  Future<void> _executePhysicalPlay(TtsAudioItem item, int session) async {
    if (session != _currentSession) return;
    // 应用最新的语速设置
    double hardwareRate = 0.5 * (_playbackRate / 1.0);
    await _flutterTts.setSpeechRate(hardwareRate.clamp(0.1, 1.0));
    // 应用最新的音色设置
    _applyVoiceSetting(_voice);
    // 缓存当前播报文本
    _currentSpeakingText = item.text;
    await _flutterTts.speak(item.text);
  }

  Future<TtsAudioRequest?> _requestNextSentence(int session) async {
    if (onNeedPrefetch == null) {
      return null;
    }
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
