import 'package:flutter/material.dart';
import '../../../core/database/storage_service.dart';
import '../domain/text_parser.dart';
import '../../audio/services/tts_engine_service.dart';
import '../../library/domain/book_model.dart';

/// 阅游提词器 Provider
/// 职责：管理 sentences 和 currentIndex，并联动 TtsEngineService 进行语音播报
class ReaderProvider with ChangeNotifier {
  final TtsEngineService _ttsEngine;
  List<String> _sentences = [];
  int _currentIndex = 0;
  int _fetchIndex = 0;
  bool _isParsing = false;
  String? _currentBookId;
  List<ChapterModel> _chapters = [];

  // 🔥 章节标题过滤正则（统一复用）
  static final RegExp _chapterRegex = RegExp(
    r'第.{1,10}[章回节卷集部篇]|Chapter\s*\d+|引子|序言|楔子',
    caseSensitive: false,
  );

  /// 判断是否为章节标题或空行
  bool _isSkippable(String text) {
    if (text.isEmpty) return true;
    return text.length < 50 && _chapterRegex.hasMatch(text);
  }

  ReaderProvider(this._ttsEngine) {
    // 生产者：为 TTS 引擎提供下一句有效文本
    _ttsEngine.onNeedPrefetch = (session) async {
      if (_sentences.isEmpty) return null;
      if (_fetchIndex >= _sentences.length) _fetchIndex = 0;

      int attempts = 0;
      while (attempts < _sentences.length) {
        final int lineIndex = _fetchIndex;
        final String text = _sentences[lineIndex].trim();
        _fetchIndex = (_fetchIndex + 1) % _sentences.length;

        if (_isSkippable(text)) {
          attempts++;
          continue;
        }

        return TtsAudioRequest(
          lineIndex: lineIndex,
          text: text,
          title: currentChapterTitle,
        );
      }
      return null;
    };

    // 🔥 onItemStarted：播放开始时，用真实 lineIndex 同步 UI
    _ttsEngine.onItemStarted = (item) {
      if (_currentIndex != item.lineIndex) {
        _currentIndex = item.lineIndex;
        notifyListeners();
      }
    };

    // 🔥 onItemFinished：播放完成时，基于真实行号推进到下一个有效句子
    _ttsEngine.onItemFinished = (item) async {
      if (_sentences.isEmpty) return;

      // 从当前播放完成的真实行号开始，找下一个有效句子
      int nextIdx = item.lineIndex + 1;
      int attempts = 0;
      while (attempts < _sentences.length && nextIdx < _sentences.length) {
        final text = _sentences[nextIdx].trim();
        if (!_isSkippable(text)) break;
        nextIdx++;
        attempts++;
      }

      if (nextIdx >= _sentences.length) {
        nextIdx = _sentences.length - 1;
      }

      _currentIndex = nextIdx;
      _fetchIndex = nextIdx;
      notifyListeners();

      _saveProgress().catchError((e) => debugPrint('⚠️ 进度保存失败: $e'));
    };
  }

  List<String> get sentences => _sentences;
  int get currentIndex => _currentIndex;
  int get fetchIndex => _fetchIndex;
  bool get isParsing => _isParsing;
  TtsEngineService get ttsEngine => _ttsEngine;
  List<ChapterModel> get chapters => _chapters;
  String? get currentBookId => _currentBookId;

  /// 计算当前章节标题（遍历 chapters，找到 lineIndex <= currentIndex 的最新章节）
  String get currentChapterTitle {
    if (_chapters.isEmpty) return '未知章节';

    ChapterModel? currentChapter;
    for (final chapter in _chapters) {
      if (chapter.lineIndex <= _currentIndex) {
        currentChapter = chapter;
      } else {
        break;
      }
    }

    return currentChapter?.title ?? _chapters.first.title;
  }

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
  Future<void> loadBook(String rawText,
      {String? bookId,
      List<ChapterModel>? chapters,
      int? initialIndex,
      bool forceIndex = false}) async {
    if (_isParsing) return;

    _isParsing = true;
    notifyListeners();

    try {
      _sentences = await TextParser.parse(rawText);
      _currentBookId = bookId;
      _chapters = chapters ?? [];

      // 恢复之前的阅读进度（对应 JS loadBookFromShelf 传入 cursor）
      int targetIndex = 0;
      if (forceIndex && initialIndex != null) {
        targetIndex = initialIndex;
      } else if (bookId != null) {
        final record = StorageService.getReadingRecord(bookId);
        final total = (record['total'] as num?)?.toInt() ?? 0;
        if (total > 1) {
          targetIndex = (record['cursor'] as num?)?.toInt() ?? 0;
        } else if (initialIndex != null) {
          targetIndex = initialIndex;
        }
      } else if (initialIndex != null) {
        targetIndex = initialIndex;
      }
      _currentIndex =
          targetIndex.clamp(0, _sentences.isEmpty ? 0 : _sentences.length - 1);
      _fetchIndex = _currentIndex;

      await StorageService.setCurrentNovelId(bookId);

      if (_ttsEngine.isEnabled) {
        _ttsEngine.refreshSession();
      }
    } catch (e) {
      debugPrint("� 神经数据加载异常 (ReaderProvider): $e");
    } finally {
      _isParsing = false;
      notifyListeners();
    }
  }

  /// 切换播放/暂停状态
  void toggleTTS() {
    _ttsEngine.setEnabled(!_ttsEngine.isEnabled);
  }

  /// 倍速切换桥接
  void cycleSpeed() {
    _ttsEngine.cycleSpeed();
  }

  /// 步进逻辑 - 进入下一句（极限性能优化版）
  Future<void> nextSentence() async {
    if (_currentIndex < _sentences.length - 1) {
      _currentIndex++;
      _fetchIndex = _currentIndex;
      notifyListeners();

      // Fire-and-forget：进度存档不阻塞主线程
      _saveProgress().catchError((e) => debugPrint('⚠️ 进度保存失败: $e'));

      // 延后半帧执行TTS刷新
      if (_ttsEngine.isEnabled) {
        Future.microtask(() => _ttsEngine.refreshSession());
      }
    }
  }

  /// 步进逻辑 - 回退上一句（极限性能优化版）
  Future<void> previousSentence() async {
    if (_currentIndex > 0) {
      _currentIndex--;
      _fetchIndex = _currentIndex;
      notifyListeners();

      // Fire-and-forget：进度存档不阻塞主线程
      _saveProgress().catchError((e) => debugPrint('⚠️ 进度保存失败: $e'));

      // 延后半帧执行TTS刷新
      if (_ttsEngine.isEnabled) {
        Future.microtask(() => _ttsEngine.refreshSession());
      }
    }
  }

  /// 按行号跳转（对应 JS jumpTo(lineIndex)）
  Future<void> jumpToLine(int index) => jumpTo(index);

  /// 🔥 切章核心：严格边界检查 + 智能跳过标题 + 同步UI + 安全重启TTS
  Future<void> jumpTo(int index) async {
    // 严格边界检查
    if (_sentences.isEmpty) return;
    if (index < 0 || index >= _sentences.length) {
      debugPrint('❌ jumpTo 拒绝: index=$index 越界 (0..${_sentences.length - 1})');
      return;
    }

    // 智能跳过章节标题和空行，找到第一个有效句子
    int targetIndex = index;
    int attempts = 0;
    while (attempts < 20 && targetIndex < _sentences.length) {
      if (!_isSkippable(_sentences[targetIndex].trim())) break;
      targetIndex++;
      attempts++;
    }
    if (targetIndex >= _sentences.length) {
      targetIndex = index; // fallback
    }

    debugPrint('✅ jumpTo: $index -> $targetIndex (总数=${_sentences.length})');

    // 🔥 第一时间同步更新，让所有 UI 瞬间响应
    _currentIndex = targetIndex;
    _fetchIndex = targetIndex;
    notifyListeners();

    // Fire-and-forget 存档
    _saveProgress().catchError((e) => debugPrint('⚠️ 进度保存失败: $e'));

    // 🔥 安全重启 TTS 流：仅在启用时才重启，避免无限后台循环
    if (_ttsEngine.isEnabled) {
      Future.microtask(() => _ttsEngine.refreshSession());
    }
  }

  /// 持久化存档逻辑（对应 JS ProgressManager.updateRecord）
  Future<void> _saveProgress() async {
    if (_currentBookId == null || _sentences.isEmpty) return;
    await StorageService.updateReadingRecord(
      _currentBookId!,
      _currentIndex,
      _sentences.length,
    );
    await StorageService.setCurrentNovelIndex(_currentIndex);
  }
}
