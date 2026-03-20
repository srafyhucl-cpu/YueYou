import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
// 1. 顶部新增引入真实的 TTS 引擎
import 'package:flutter_tts/flutter_tts.dart';

/// 阅游全息 TTS 发声引擎
/// 职责：管理 TTS 预加载队列、播控状态机、多倍速循环逻辑
/// 1:1 复刻老代码中的 startPrefetchLoop 与 startPlayLoop 状态机架构
class TtsEngineService extends ChangeNotifier {
  bool _isEnabled = false;
  bool _isSpeaking = false;
  bool _isBuffering = false;
  double _playbackRate = 1.0;
  final List<double> _speedTiers = [1.0, 1.2, 1.5, 2.0, 2.5, 0.7];
  final Queue<TtsAudioItem> _audioBufferQueue = Queue<TtsAudioItem>();
  int _currentSession = 1;
  bool _playLoopActive = false;
  bool _prefetchLoopActive = false;
  TtsAudioItem? _currentItem;
  Completer<void>? _playInterruptCompleter;

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

  // 3. 新增构造函数，进行底层硬件初始化
  TtsEngineService() {
    _initTtsHardware();
  }

  Future<void> _initTtsHardware() async {
    _flutterTts = FlutterTts();
    await _flutterTts.setLanguage("zh-CN"); // 锁定中文链路
    // 强制开启"等待语音播报完毕才返回 Future"的极客特性，这与我们的状态机完美契合！
    await _flutterTts.awaitSpeakCompletion(true);
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

  void cycleSpeed() {
    final int currentIndex = _speedTiers.indexOf(_playbackRate);
    final int nextIndex = (currentIndex + 1) % _speedTiers.length;
    _playbackRate = _speedTiers[nextIndex];

    // 硬件级倍速同步 (FlutterTts 的 speechRate 范围通常是 0.0 到 1.0，0.5 相当于正常语速)
    // 这里做一个简单的映射，防止语速过快变成电报音
    double hardwareRate = 0.5 * (_playbackRate / 1.0);
    _flutterTts.setSpeechRate(hardwareRate.clamp(0.1, 1.0));

    notifyListeners();
  }

  /// 从设置页直接同步倍速（对应 JS updateSetting('voice'/'ttsRate') 调用链）
  void syncSpeedFromSettings(double logicalRate, double hardwareRate) {
    _playbackRate = logicalRate;
    _flutterTts.setSpeechRate(hardwareRate.clamp(0.1, 1.0));
    notifyListeners();
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
    if (changed) {
      notifyListeners();
    }
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
    // 只要系统喇叭没有被 setEnabled(false) 拦截，就一直说话
    if (session == _currentSession && _isEnabled) {
      // 这句 await 会一直阻塞，直到这行字从手机喇叭里完完整整地念完！
      await _flutterTts.speak(item.text);
    }
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
