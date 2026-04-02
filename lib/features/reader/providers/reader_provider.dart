import 'package:flutter/material.dart';
import '../../../core/database/storage_service.dart';
import '../domain/text_parser.dart';
import '../../audio/services/tts_engine_service.dart';
import '../../library/domain/book_model.dart';

/// 阅游提词器 Provider
/// 职责：管理 sentences 和 currentIndex，并联动 TtsEngineService 进行语音播报
class ReaderProvider with ChangeNotifier {
  final TtsEngineService _ttsEngine;
  final Future<ParseResult> Function(String rawText) _parseBook;
  List<String> _sentences = [];
  int _currentIndex = 0;
  int _fetchIndex = 0;
  bool _isParsing = false;
  String? _currentBookId;
  List<ChapterModel> _chapters = [];
  String? _lastTtsError;

  // 🔥 章节标题正则（与 file_import_service 同步）
  static final RegExp _chapterRegex = RegExp(
    r'^\s*(?:(?:正文|卷[0-9零一二三四五六七八九十百千两\s]+|.{0,4})\s*第?\s*[0-9零一二三四五六七八九十百千两]+\s*[章回节卷集部篇]|Chapter\s*[0-9]+|引子|序言|楔子|前言|内容简介|致读者)',
    caseSensitive: false,
  );

  // 🔥 噪音词正则：独立出现的「正文」「VIP卷」「默认卷」等无意义行
  static final RegExp _noiseRegex = RegExp(
    r'^\s*(正文|正\s*文|正文卷|VIP卷|默认卷|上架感言|作品相关|\*{3,}|\-{3,}|={3,})\s*$',
    caseSensitive: false,
  );

  // 🔥 标题清洗正则：移除标题中的垃圾前缀词
  static final RegExp _titleGarbageRegex = RegExp(r'(正文|VIP卷|默认卷)');

  /// 清洗章节标题：移除「正文」「VIP卷」等垃圾前缀
  static String cleanChapterTitle(String raw) {
    return raw.replaceAll(_titleGarbageRegex, '').trim();
  }

  /// 噪音/空行判定（TTS 和游标均应跳过，绝不朗读）
  bool _isNoise(String text) {
    if (text.isEmpty) return true;
    if (_noiseRegex.hasMatch(text)) return true;
    return false;
  }

  /// 章节标题判定（TTS 应朗读，但需要清洗）
  bool _isChapterTitle(String text) {
    return text.isNotEmpty && text.length < 50 && _chapterRegex.hasMatch(text);
  }

  ReaderProvider(
    this._ttsEngine, {
    Future<ParseResult> Function(String rawText)? parseBook,
  }) : _parseBook = parseBook ?? TextParser.parse {
    _lastTtsError = _ttsEngine.lastError;
    _ttsEngine.addListener(_onTtsEngineChanged);

    // 生产者：为 TTS 引擎提供下一句有效文本
    // 🔥 重写核心：_fetchIndex 在此处立即推进，跳过所有已消耗行（含合并短句）
    _ttsEngine.onNeedPrefetch = (session) async {
      if (_sentences.isEmpty) return null;
      if (_fetchIndex >= _sentences.length) _fetchIndex = 0;

      int cursor = _fetchIndex;
      int scanned = 0;

      while (scanned < _sentences.length) {
        final int lineIndex = cursor;
        String text = _sentences[lineIndex].trim();

        // 跳过噪音词和空行（始终不读）
        if (_isNoise(text)) {
          cursor = (cursor + 1) % _sentences.length;
          scanned++;
          continue;
        }

        // 🔥 章节标题 → 清洗后朗读（如「正文 第一章 新的开始」→「第一章 新的开始」）
        if (_isChapterTitle(text)) {
          text = cleanChapterTitle(text);
          if (text.isEmpty) {
            cursor = (cursor + 1) % _sentences.length;
            scanned++;
            continue;
          }
        }

        // TTS API 要求至少 5 字符，向后合并短句
        int consumed = cursor + 1; // consumed 指向「下一个未消耗行」
        while (text.length < 5 && consumed < _sentences.length) {
          final nextText = _sentences[consumed].trim();
          consumed++;
          if (_isNoise(nextText)) continue;
          // 合并时遇到下一个章节标题则停止，不跨章合并
          if (_isChapterTitle(nextText)) break;
          text = text + nextText;
          if (text.length >= 5) break;
        }

        // 合并后仍然太短 → 跳过整段
        if (text.length < 5) {
          cursor = consumed % _sentences.length;
          scanned += (consumed - lineIndex);
          continue;
        }

        // 🔥 立即推进 _fetchIndex 到所有已消耗行之后，杜绝重复
        _fetchIndex = consumed < _sentences.length
            ? consumed
            : consumed % _sentences.length;

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
      if (item.session != _ttsEngine.currentSession) {
        return;
      }
      if (_currentIndex != item.lineIndex) {
        _currentIndex = item.lineIndex;
        notifyListeners();
      }
    };

    // 🔥 onItemFinished：播放完成时，只更新 _currentIndex（UI显示），不修改 _fetchIndex（预加载游标）
    _ttsEngine.onItemFinished = (item) async {
      if (item.session != _ttsEngine.currentSession) {
        return;
      }
      if (_sentences.isEmpty) return;

      // 从当前播放完成的真实行号开始，找下一个有效句子（噪音跳过，章节标题保留）
      int nextIdx = item.lineIndex + 1;
      int attempts = 0;
      while (attempts < _sentences.length && nextIdx < _sentences.length) {
        final text = _sentences[nextIdx].trim();
        if (!_isNoise(text)) break;
        nextIdx++;
        attempts++;
      }

      if (nextIdx >= _sentences.length) {
        nextIdx = _sentences.length - 1;
      }

      // 🔥 只更新 _currentIndex，不修改 _fetchIndex（避免干扰预加载循环）
      _currentIndex = nextIdx;
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
  String? get ttsErrorMessage => _lastTtsError;

  /// 清理当前 TTS 错误提示（例如 UI 已展示并确认后）。
  void clearTtsError() {
    _ttsEngine.clearLastError();
  }

  void _onTtsEngineChanged() {
    bool changed = false;
    final nextError = _ttsEngine.lastError;
    if (nextError != _lastTtsError) {
      _lastTtsError = nextError;
      changed = true;
    }
    // 🔥 关键修复：TTS 引擎的播放状态变化必须同步给 ReaderProvider 的监听者（如提词器）
    // 否则暂停时提词器无法立即感知到 isSpeaking 的变化，导致动画继续执行到结束
    changed = true;

    if (changed) {
      notifyListeners();
    }
  }

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

    final raw = currentChapter?.title ?? _chapters.first.title;
    return cleanChapterTitle(raw);
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
      final parseResult = await _parseBook(rawText);
      _sentences = parseResult.sentences;
      _currentBookId = bookId;

      // 🔥 构建原始行号 → sentences 索引的映射（取每个原始行产生的第一个 sentence）
      final Map<int, int> rawLineToSentIdx = {};
      for (int i = 0; i < parseResult.rawLineOrigins.length; i++) {
        rawLineToSentIdx.putIfAbsent(parseResult.rawLineOrigins[i], () => i);
      }

      // 🔥 重建 chapter.lineIndex：从原始行号映射到 sentences 索引 + 清洗标题
      final rawChapters = chapters ?? <ChapterModel>[];
      _chapters = rawChapters.map((c) {
        final cleaned = cleanChapterTitle(c.title);
        final mappedIdx = rawLineToSentIdx[c.lineIndex] ?? c.lineIndex;
        return ChapterModel(title: cleaned, lineIndex: mappedIdx);
      }).toList();

      // 恢复之前的阅读进度（对应 JS loadBookFromShelf 传入 cursor）
      int targetIndex = 0;
      if (initialIndex != null) {
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
    if (_ttsEngine.isSpeaking) {
      _ttsEngine.pause();
    } else {
      _ttsEngine.play();
    }
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

    // 智能跳过噪音和空行，保留章节标题（让 TTS 从标题开始朗读）
    int targetIndex = index;
    int attempts = 0;
    while (attempts < 20 && targetIndex < _sentences.length) {
      if (!_isNoise(_sentences[targetIndex].trim())) break;
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

  void switchChapter(int chapterIndex) {
    if (_chapters.isEmpty) return;
    if (chapterIndex < 0 || chapterIndex >= _chapters.length) return;
    _currentIndex = _chapters[chapterIndex].lineIndex;
    _fetchIndex = _chapters[chapterIndex].lineIndex;
    _ttsEngine.refreshSession();
    notifyListeners();
    _saveProgress();
  }

  @override
  void dispose() {
    _ttsEngine.removeListener(_onTtsEngineChanged);
    super.dispose();
  }
}
