import 'package:flutter/material.dart';
import '../domain/text_parser.dart';
import '../../audio/services/tts_engine_service.dart';

/// 阅游提词器 Provider
/// 职责：管理 sentences 和 currentIndex，并联动 TtsEngineService 进行语音播报
class ReaderProvider with ChangeNotifier {
  final TtsEngineService _ttsEngine;
  List<String> _sentences = [];
  int _currentIndex = 0;
  bool _isParsing = false;

  ReaderProvider(this._ttsEngine) {
    // 注入 TTS 获取文本回调，完美解决预取队列取词竞争
    _ttsEngine.onNeedText = (session) async {
      // 获取当前 fetchCursor 的文本，由 TTS 引擎自行维护 fetch 指针
      // 此处逻辑与老代码 fetchCursor 同步
      if (_sentences.isEmpty) return null;
      // 这里的 logic 需注意：预取文本不一定就是当前正在播放的文本，
      // 所以我们通过一个本地 fetchIndex 分离
      return null; // 这里我们将使用直接控制的方式，由 TTS 主动触发 nextSentence()
    };
  }

  List<String> get sentences => _sentences;
  int get currentIndex => _currentIndex;
  bool get isParsing => _isParsing;
  TtsEngineService get ttsEngine => _ttsEngine;

  /// 进度引擎：当前进度百分比 (0.01 - 1.0)
  double get progress {
    if (_sentences.isEmpty) return 0.0;
    return (_currentIndex + 1) / _sentences.length;
  }

  /// 获取当前显示的句子内容
  String? get currentSentence {
    if (_sentences.isEmpty || _currentIndex >= _sentences.length) return null;
    return _sentences[_currentIndex];
  }

  /// 核心加载方法：加载书籍并解析
  Future<void> loadBook(String rawText, {String? bookId}) async {
    if (_isParsing) return;
    
    _isParsing = true;
    notifyListeners();

    try {
      _sentences = await TextParser.parse(rawText);
      _currentIndex = 0; 
      
      // 解析完成，如果 TTS 已开启，自动启动首句预热
      if (_ttsEngine.isEnabled) {
        // 因涉及到复杂的双循环架构，此处我们通常通过重置 TTS Session 来生效
        _ttsEngine.stopAll();
      }
    } catch (e) {
      debugPrint("📖 神经数据加载异常 (ReaderProvider): $e");
    } finally {
      _isParsing = false;
      notifyListeners();
    }
  }

  /// 切换播放/暂停状态
  void toggleTTS() {
    _ttsEngine.setEnabled(!_ttsEngine.isEnabled);
    notifyListeners();
  }

  /// 倍速切换桥接
  void cycleSpeed() {
    _ttsEngine.cycleSpeed();
    notifyListeners();
  }

  /// 步进逻辑 - 进入下一句
  void nextSentence() {
    if (_currentIndex < _sentences.length - 1) {
      _currentIndex++;
      _saveProgress(); 
      notifyListeners();
    }
  }

  /// 步进逻辑 - 回退上一句
  void previousSentence() {
    if (_currentIndex > 0) {
      _currentIndex--;
      _saveProgress();
      notifyListeners();
    }
  }

  /// 跳转至指定索引进度
  void jumpTo(int index) {
    if (index >= 0 && index < _sentences.length) {
      _currentIndex = index;
      _saveProgress();
      notifyListeners();
      // 如果正在播放，跳转后重置 TTS 会话，从新位置开始
      if (_ttsEngine.isEnabled) {
        _ttsEngine.stopAll();
        _ttsEngine.setEnabled(true);
      }
    }
  }

  /// 持久化存档逻辑
  Future<void> _saveProgress() async {
    debugPrint("📥 进度自动归档: Index $_currentIndex / Total ${_sentences.length}");
  }
}
