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

  ReaderProvider(this._ttsEngine) {
    _ttsEngine.onNeedPrefetch = (session) async {
      if (_sentences.isEmpty) {
        return null;
      }
      if (_fetchIndex >= _sentences.length) {
        _fetchIndex = 0;
      }
      final int lineIndex = _fetchIndex;
      final String text = _sentences[lineIndex].trim();
      _fetchIndex = (_fetchIndex + 1) % _sentences.length;
      if (text.isEmpty) {
        return TtsAudioRequest(
          lineIndex: lineIndex,
          text: '',
          title: currentChapterTitle,
        );
      }
      return TtsAudioRequest(
        lineIndex: lineIndex,
        text: text,
        title: currentChapterTitle,
      );
    };
    _ttsEngine.onItemStarted = (item) {
      if (_currentIndex != item.lineIndex) {
        _currentIndex = item.lineIndex;
        notifyListeners();
      }
    };
    _ttsEngine.onItemFinished = (item) async {
      if (_sentences.isEmpty) {
        return;
      }
      _currentIndex = (_currentIndex + 1) % _sentences.length;
      await _saveProgress();
      notifyListeners();
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

  /// 步进逻辑 - 进入下一句
  Future<void> nextSentence() async {
    if (_currentIndex < _sentences.length - 1) {
      _currentIndex++;
      _fetchIndex = _currentIndex;
      await _saveProgress();
      if (_ttsEngine.isEnabled) {
        _ttsEngine.refreshSession();
      }
      notifyListeners();
    }
  }

  /// 步进逻辑 - 回退上一句
  Future<void> previousSentence() async {
    if (_currentIndex > 0) {
      _currentIndex--;
      _fetchIndex = _currentIndex;
      await _saveProgress();
      if (_ttsEngine.isEnabled) {
        _ttsEngine.refreshSession();
      }
      notifyListeners();
    }
  }

  /// 按行号跳转（对应 JS jumpTo(lineIndex)）
  Future<void> jumpToLine(int index) => jumpTo(index);

  /// 跳转至指定索引进度
  Future<void> jumpTo(int index) async {
    if (index >= 0 && index < _sentences.length) {
      _currentIndex = index;
      _fetchIndex = index;
      await _saveProgress();
      if (_ttsEngine.isEnabled) {
        _ttsEngine.refreshSession();
      }
      notifyListeners();
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
