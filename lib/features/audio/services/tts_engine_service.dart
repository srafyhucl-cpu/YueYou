import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';

/// 阅游全息 TTS 发声引擎
/// 职责：管理 TTS 预加载队列、播控状态机、多倍速循环逻辑
/// 1:1 复刻老代码中的 startPrefetchLoop 与 startPlayLoop 状态机架构
class TtsEngineService extends ChangeNotifier {
  // --- 核心发声状态 (1:1 提取 AudioManager.js) ---
  bool _isEnabled = false;
  bool _isSpeaking = false;
  bool _isBuffering = false;
  double _playbackRate = 1.0;
  
  // 倍速档位循环定义
  final List<double> _speedTiers = [1.0, 1.2, 1.5, 2.0, 2.5, 0.7];

  // 模拟播放列表与预加载队列 (audioBufferArray)
  final Queue<TtsAudioItem> _audioBufferQueue = Queue<TtsAudioItem>();
  
  // 核心会话计数器 (loopSession)
  int _currentSession = 1;
  
  // 内部控制句柄
  Completer<void>? _currentPlayCompleter;

  // 公开属性
  bool get isEnabled => _isEnabled;
  bool get isSpeaking => _isSpeaking;
  bool get isBuffering => _isBuffering;
  double get playbackRate => _playbackRate;

  // ======================================
  // 接口定义 (Play / Pause / Speed / Stop)
  // ======================================

  void setEnabled(bool enable) {
    if (_isEnabled == enable) return;
    _isEnabled = enable;
    if (!enable) {
      stopAll();
    } else {
      _startLoops();
    }
    notifyListeners();
  }

  void stopAll() {
    _currentSession++; // 物理隔离：通过递增 Session ID 阻止所有正在进行的异步回调
    _isSpeaking = false;
    _isBuffering = false;
    _audioBufferQueue.clear();
    _currentPlayCompleter?.complete();
    _currentPlayCompleter = null;
    notifyListeners();
  }

  /// 循环切换倍速 (1.0 -> 1.2 -> 1.5 -> 2.0 -> 2.5 -> 0.7)
  void cycleSpeed() {
    int currentIndex = _speedTiers.indexOf(_playbackRate);
    int nextIndex = (currentIndex + 1) % _speedTiers.length;
    _playbackRate = _speedTiers[nextIndex];
    notifyListeners();
    // 倍速改变后可在此持久化存储
  }

  // ======================================
  // 核心状态机实现 (复刻老项目双循环)
  // ======================================

  void _startLoops() {
    _startPrefetchLoop();
    _startPlayLoop();
  }

  /// 预取循环：保持预加载深度为 5 句 (1:1 复刻 Web 端的深预取逻辑)
  Future<void> _startPrefetchLoop() async {
    while (_isEnabled) {
      final int sessionSnapshot = _currentSession;
      
      // 检查队列长度与解析状态
      if (_audioBufferQueue.length >= 5) {
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }

      // 🚨 获取文本逻辑（实际会由 ReaderProvider 驱动或直接访问 Provider）
      // 此处假设外部会将句子推入到一个待处理池，或通过回调获取
      String? nextText = await _requestNextSentence(sessionSnapshot);
      if (nextText == null) {
        await Future.delayed(const Duration(seconds: 1));
        continue;
      }

      // 模拟 fetchTTS 异步网络请求
      _isBuffering = _audioBufferQueue.isEmpty; 
      if (_isBuffering) notifyListeners();

      TtsAudioItem? item = await _fetchTtsAsset(nextText, sessionSnapshot);
      
      // 会话安全检查：如果网络返回时 session 已变，直接丢弃
      if (sessionSnapshot != _currentSession) continue;

      if (item != null) {
        _audioBufferQueue.add(item);
        _isBuffering = false;
        notifyListeners();
      }
    }
  }

  /// 播放循环：主线程异步串行播放机
  Future<void> _startPlayLoop() async {
    while (_isEnabled) {
      final int sessionSnapshot = _currentSession;

      if (_audioBufferQueue.isEmpty) {
        _isSpeaking = false;
        _isBuffering = true;
        notifyListeners();
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }

      _isBuffering = false;
      final TtsAudioItem item = _audioBufferQueue.removeFirst();
      
      // 确保播放前杀死一切之前的残留
      _isSpeaking = true;
      notifyListeners();

      _currentPlayCompleter = Completer<void>();
      
      // 执行真实物理音频播放逻辑 (此处为 Mock，对接 flutter_tts 或 API)
      await _executePhysicalPlay(item, sessionSnapshot);

      if (sessionSnapshot != _currentSession) continue;
      
      // 播放正常结束，通知 UI 或 ReaderProvider 更新进度
      _onAudioFinished(item);
    }
  }

  // ======================================
  // 内部辅助方法 (Mock 部分)
  // ======================================

  Future<TtsAudioItem?> _fetchTtsAsset(String text, int session) async {
    // 模拟 500ms 网络延迟获取音频流
    await Future.delayed(const Duration(milliseconds: 500));
    return TtsAudioItem(text: text, id: DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _executePhysicalPlay(TtsAudioItem item, int session) async {
    // 模拟根据文本长度计算的播放时长 (字数 / 字频 * 倍速)
    double durationSec = (item.text.length / 4.5) / _playbackRate;
    await Future.delayed(Duration(milliseconds: (durationSec * 1000).toInt()));
  }

  void _onAudioFinished(TtsAudioItem item) {
    // 触发 ReaderProvider 步进
    notifyListeners();
  }

  // 这是一个由 ReaderProvider 注入的钩子，用于获取文本
  Future<String?> Function(int session)? onNeedText;
  Future<String?> _requestNextSentence(int session) async {
    if (onNeedText != null) return onNeedText!(session);
    return null;
  }
}

/// 音频缓存模型
class TtsAudioItem {
  final String text;
  final int id;
  TtsAudioItem({required this.text, required this.id});
}
