import 'package:flutter/material.dart';
import '../../../core/database/storage_service.dart';
import 'package:yueyou/features/reader/domain/text_parser.dart';
import '../../audio/services/tts_engine_service.dart';
import '../../library/domain/book_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 阻读器全局 Provider（Riverpod 生命周期托管版）
///
/// - 通过 [ref.read] 获取 [ttsEngineProvider]，避免不必要的重建
/// - 通过 [ref.onDispose] 自动回收阻读器资源
/// - 不使用 ref.watch(ttsEngineProvider)，避免 TTS 变化触发 ReaderProvider 重建
final readerProvider = ChangeNotifierProvider<ReaderProvider>((ref) {
  final tts = ref.read(ttsEngineProvider);
  final rp = ReaderProvider(tts);
  // 注册 Riverpod 自动销毁钩子
  ref.onDispose(rp.dispose);
  return rp;
});

/// TTS 切换操作的领域结果
enum TtsToggleResult {
  /// 成功切换到播放
  playing,

  /// 成功切换到暂停
  paused,

  /// 无有效书籍数据，无法开启 TTS
  noContent,
}

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
  TtsPlaybackState _lastTtsState = TtsPlaybackState.disabled;

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
    _lastTtsState = _ttsEngine.state;
    _ttsEngine.addListener(_onTtsEngineChanged);

    // 生产者：为 TTS 引擎提供下一句有效文本
    // 🔥 重写核心：_fetchIndex 在此处立即推进，跳过所有已消耗行（含合并短句）
    _ttsEngine.onNeedPrefetch = (session) async {
      if (_sentences.isEmpty) return null;
      if (_fetchIndex >= _sentences.length) {
        debugPrint(' [TtsFetch] 已到达书籍末尾 (fetch=$_fetchIndex)');
        return null;
      }

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
        if (consumed >= _sentences.length) {
          // 到达书籍末尾，不再推进 _fetchIndex，由下一次调用返回 null 终止
          _fetchIndex = _sentences.length;
        } else {
          _fetchIndex = consumed;
        }

        debugPrint(' [TtsFetch] 提交请求: line=$lineIndex, nextFetch=$_fetchIndex, text="${text.substring(0, text.length > 10 ? 10 : text.length)}..."');

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

      // 🔥 自动步进：跳过噪音行并推进 currentIndex
      int nextIdx = _currentIndex + 1;
      while (nextIdx < _sentences.length && _isNoise(_sentences[nextIdx])) {
        nextIdx++;
      }

      if (nextIdx < _sentences.length) {
        _currentIndex = nextIdx;
        // 🔥 重要修复：此处绝不可重置 _fetchIndex！
        // 预取指针应当保持领先，重置它会导致预取循环重新抓取已在队列中的任务。
        notifyListeners();
      }

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

    final nextState = _ttsEngine.state;
    if (nextState != _lastTtsState) {
      _lastTtsState = nextState;
      changed = true;
    }

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
    final currentItem = _ttsEngine.currentItem;
    if (currentItem != null &&
        currentItem.session == _ttsEngine.currentSession &&
        currentItem.text.trim().isNotEmpty) {
      return currentItem.text;
    }
    if (_sentences.isEmpty || _currentIndex >= _sentences.length) return null;
    return _sentences[_currentIndex];
  }

  Future<void> _applyLoadedBook({
    required List<String> sentences,
    required List<int> rawLineOrigins,
    String? bookId,
    List<ChapterModel>? chapters,
    int? initialIndex,
  }) async {
    _sentences = sentences;
    _currentBookId = bookId;

    final Map<int, int> rawLineToSentIdx = {};
    for (int i = 0; i < rawLineOrigins.length; i++) {
      rawLineToSentIdx.putIfAbsent(rawLineOrigins[i], () => i);
    }

    final rawChapters = chapters ?? <ChapterModel>[];
    _chapters = rawChapters.map((c) {
      final cleaned = cleanChapterTitle(c.title);
      final mappedIdx = rawLineToSentIdx[c.lineIndex] ?? c.lineIndex;
      return ChapterModel(title: cleaned, lineIndex: mappedIdx);
    }).toList();

    int targetIndex = 0;
    if (initialIndex != null) {
      targetIndex = initialIndex;
    } else if (bookId != null) {
      final record = StorageService.getReadingRecord(bookId);
      final total = (record['total'] as num?)?.toInt() ?? 0;
      if (total > 1) {
        targetIndex = (record['cursor'] as num?)?.toInt() ?? 0;
      }
    }

    _currentIndex =
        targetIndex.clamp(0, _sentences.isEmpty ? 0 : _sentences.length - 1);
    _fetchIndex = _currentIndex;

    await StorageService.setCurrentNovelId(bookId);

    if (_ttsEngine.isEnabled) {
      _ttsEngine.refreshSession();
    }
  }

  Future<void> loadPreparedBook(
    List<String> lines, {
    String? bookId,
    List<ChapterModel>? chapters,
    int? initialIndex,
  }) async {
    if (_isParsing) return;

    _isParsing = true;
    notifyListeners();

    try {
      final List<String> sentences = lines
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
      final List<int> rawLineOrigins = List<int>.generate(
        sentences.length,
        (index) => index,
        growable: false,
      );
      await _applyLoadedBook(
        sentences: sentences,
        rawLineOrigins: rawLineOrigins,
        bookId: bookId,
        chapters: chapters,
        initialIndex: initialIndex,
      );
    } catch (e) {
      debugPrint('ReaderProvider.loadPreparedBook error: $e');
    } finally {
      _isParsing = false;
      notifyListeners();
    }
  }

  /// 核心加载方法：加载书籍并解析
  Future<void> loadBook(String rawText,
      {String? bookId,
      List<ChapterModel>? chapters,
      int? initialIndex,
      bool forceIndex = false,}) async {
    if (_isParsing) return;

    _isParsing = true;
    notifyListeners();

    try {
      final parseResult = await _parseBook(rawText);
      await _applyLoadedBook(
        sentences: parseResult.sentences,
        rawLineOrigins: parseResult.rawLineOrigins,
        bookId: bookId,
        chapters: chapters,
        initialIndex: initialIndex,
      );
    } catch (e) {
      debugPrint('� 神经数据加载异常 (ReaderProvider): $e');
    } finally {
      _isParsing = false;
      notifyListeners();
    }
  }

  /// 切换播放/暂停状态
  /// 返回领域结果，由 UI 层决定如何展示提示
  ///
  /// 使用 Dart 3 穷尽 switch 表达式，确保 [TtsPlaybackState] 所有
  /// 状态分支在编译期得到穷尽性检查，消除静默失败风险。
  TtsToggleResult toggleTTS() {
    // 前置拦截——未导入书籍或数据为空时，禁止触发 TTS
    if (_currentBookId == null || _sentences.isEmpty) {
      return TtsToggleResult.noContent;
    }
    // 穷尽 switch：覆盖 TtsPlaybackState 全部 5 个分支
    return switch (_ttsEngine.state) {
      // 播放中 / 缓冲中 → 暂停
      TtsPlaybackState.playing ||
      TtsPlaybackState.buffering =>
        () {
          _ttsEngine.pause();
          return TtsToggleResult.paused;
        }(),
      // 已暂停 / 已关闭 → 播放
      TtsPlaybackState.paused ||
      TtsPlaybackState.disabled =>
        () {
          _ttsEngine.play();
          return TtsToggleResult.playing;
        }(),
      // 错误状态 → 清除错误后尝试恢复播放
      TtsPlaybackState.error => () {
          _ttsEngine.clearLastError();
          _ttsEngine.play();
          return TtsToggleResult.playing;
        }(),
    };
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

  /// 🔥 任务 1.3：级联重置——当当前正在阅读的书籍被删除时，完全重置阅读器状态
  void resetForDeletedBook(String bookId) {
    if (_currentBookId != bookId) return;

    // 停止 TTS 播放
    if (_ttsEngine.isEnabled) {
      _ttsEngine.setEnabled(false);
    }

    // 置空所有数据
    _currentBookId = null;
    _sentences = [];
    _chapters = [];
    _currentIndex = 0;
    _fetchIndex = 0;

    // 异步清除持久化的当前小说标识
    StorageService.setCurrentNovelId(null);

    notifyListeners();
    debugPrint('🗑️ 级联重置：书籍 $bookId 已删除，ReaderProvider 已清空');
  }

  @override
  void dispose() {
    _ttsEngine.removeListener(_onTtsEngineChanged);
    // 🔥 清理回调占用，防止闭包捕获已销毁的 ReaderProvider
    if (_ttsEngine.onNeedPrefetch != null) {
      _ttsEngine.onNeedPrefetch = null;
    }
    if (_ttsEngine.onItemStarted != null) {
      _ttsEngine.onItemStarted = null;
    }
    if (_ttsEngine.onItemFinished != null) {
      _ttsEngine.onItemFinished = null;
    }
    super.dispose();
  }
}
