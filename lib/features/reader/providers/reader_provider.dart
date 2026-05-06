import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';
import '../../../core/constants/book_constants.dart';
import '../../../core/utils/text_processing.dart';
import '../../../core/database/storage_service.dart';
import 'package:yueyou/features/audio/providers/tts_audio_notifier.dart';
import 'package:yueyou/features/library/services/default_book_service.dart';
import 'package:yueyou/features/reader/domain/chapter_load_state.dart';
import 'package:yueyou/features/reader/domain/text_parser.dart';
import '../../audio/services/tts_engine_service.dart';
import '../../library/domain/book_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 阻读器全局 Provider（Riverpod 生命周期托管版）
///
/// - 通过 [ref.read] 获取 [ttsEngineProvider] 用于影子状态监听
/// - 通过 [ref.read] 获取 [ttsAudioProvider.notifier] 注册句子源
/// - 通过 [ref.onDispose] 自动回收阻读器资源
final readerProvider = ChangeNotifierProvider<ReaderProvider>((ref) {
  final engine = ref.read(ttsEngineProvider);
  final notifier = ref.read(ttsAudioProvider.notifier);
  final rp = ReaderProvider(engine, notifier: notifier);
  notifier.registerSentenceSource(rp);
  ref.onDispose(rp.dispose);
  // 热重启恢复：若上次阅读的是默认书籍，自动重载当前章节
  final lastNovelId = StorageService.getCurrentNovelId();
  if (lastNovelId == BookConstants.defaultBookKey) {
    Future.microtask(() => rp.restoreDefaultBook());
  }
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
class ReaderProvider with ChangeNotifier implements TtsSentenceSource {
  final TtsEngineService _ttsEngine;
  final TtsAudioNotifier? _ttsNotifier;
  final Future<ParseResult> Function(String rawText) _parseBook;
  List<String> _sentences = [];
  int _currentIndex = 0;
  int _fetchIndex = 0;
  bool _isParsing = false;
  String? _currentBookId;
  List<ChapterModel> _chapters = [];
  String? _lastTtsError;
  TtsPlaybackState _lastTtsState = TtsPlaybackState.disabled;

  // ── 分章懒加载（默认书籍模式）──────────────────────────────────────────────
  int? _currentChapterIndex;
  ChapterLoadState _chapterLoadState = ChapterLoadState.idle;
  bool _isDefaultBookMode = false;
  DefaultBookService? _defaultBookService;

  /// 噪音/空行判定（TTS 和游标均应跳过，绝不朗读）
  bool _isNoise(String text) => TextProcessing.isNoiseLine(text);

  /// 章节标题判定（TTS 应朗读，但需要清洗）
  bool _isChapterTitle(String text) => TextProcessing.isChapterTitle(text);

  ReaderProvider(
    this._ttsEngine, {
    TtsAudioNotifier? notifier,
    Future<ParseResult> Function(String rawText)? parseBook,
  })  : _ttsNotifier = notifier,
        _parseBook = parseBook ?? TextParser.parse {
    _lastTtsError = _ttsEngine.lastError;
    _lastTtsState = _ttsEngine.state;
    _ttsEngine.addListener(_onTtsEngineChanged);
    // 句子源回调由 TtsAudioNotifier 通过 registerSentenceSource 注册
  }

  @override
  Future<TtsAudioRequest?> nextTtsSentence(int session) async {
    if (_sentences.isEmpty) return null;
    if (_fetchIndex >= _sentences.length) {
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
        text = TextProcessing.cleanChapterTitle(text);
        if (text.isEmpty) {
          cursor = (cursor + 1) % _sentences.length;
          scanned++;
          continue;
        }
      }

      // TTS API 要求至少 5 字符，向后合并短句
      int consumed = cursor + 1; // consumed 指向「下一个未消耗行」
      int endLine = lineIndex; // 合并消耗到的最后一行（含）
      while (text.length < 5 && consumed < _sentences.length) {
        final mergeIdx = consumed;
        final nextText = _sentences[mergeIdx].trim();
        consumed++;
        if (_isNoise(nextText)) continue;
        // 合并时遇到下一个章节标题则停止，不跨章合并
        if (_isChapterTitle(nextText)) break;
        text = text + nextText;
        endLine = mergeIdx;
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

      return TtsAudioRequest(
        lineIndex: lineIndex,
        endLineIndex: endLine,
        text: text,
        title: currentChapterTitle,
      );
    }
    return null;
  }

  /// 播放开始时，用真实 lineIndex 同步 UI。
  @override
  FutureOr<void> onTtsItemStarted(TtsAudioItem item) {
    final session = _ttsNotifier?.currentSession;
    // 无编排层时跳过 session 校验（向下兼容）
    if (session != null && item.session != session) return null;
    if (_currentIndex != item.lineIndex) {
      _currentIndex = item.lineIndex;
      notifyListeners();
    }
  }

  /// 播放完成时只更新 UI 游标，不修改预加载游标。
  @override
  Future<void> onTtsItemFinished(TtsAudioItem item) async {
    final session = _ttsNotifier?.currentSession;
    // 无编排层时跳过 session 校验（向下兼容）
    if (session != null && item.session != session) return;
    if (_sentences.isEmpty) return;

    // 🔥 自动步进：从「合并段最后一行」之后开始扫描，跳过噪音行
    // 关键：item.endLineIndex 已包含本句合并消耗的所有行，
    // 使用它推进可保证提词器不跳行、与 TTS 进度严格对齐。
    int nextIdx = item.endLineIndex + 1;
    if (nextIdx <= _currentIndex) nextIdx = _currentIndex + 1;
    while (nextIdx < _sentences.length && _isNoise(_sentences[nextIdx])) {
      nextIdx++;
    }

    if (nextIdx < _sentences.length) {
      _currentIndex = nextIdx;
      // 🔥 重要修复：此处绝不可重置 _fetchIndex！
      // 预取指针应当保持领先，重置它会导致预取循环重新抓取已在队列中的任务。
      notifyListeners();
    } else {
      // 章节末尾：先钉住 UI 游标到当前句位置
      if (item.lineIndex >= 0 && item.lineIndex < _sentences.length) {
        _currentIndex = item.lineIndex;
        notifyListeners();
      }
      // 🔥 章节末尾 + 默认书籍模式：自动推进到下一章
      // 注意：必须与上方 UI 更新分离（不可用 else if），二者应同时执行
      if (_isDefaultBookMode) {
        _autoAdvanceChapter();
      }
    }

    _saveProgress().catchError((e) {
      CyberLogger.captureWarning(
        e,
        tag: 'reader',
        extra: {'context': 'onTtsItemFinished 进度保存失败'},
      );
    });
  }

  /// 重置预取游标到当前阅读位置。
  @override
  void resetFetchIndex() {
    _fetchIndex = _currentIndex;
  }

  List<String> get sentences => _sentences;
  int get currentIndex => _currentIndex;
  int get fetchIndex => _fetchIndex;
  bool get isParsing => _isParsing;
  TtsEngineService get ttsEngine => _ttsEngine;
  List<ChapterModel> get chapters => _chapters;
  String? get currentBookId => _currentBookId;
  String? get ttsErrorMessage => _lastTtsError;

  // ── 分章懒加载 getter ─────────────────────────────────────────────────────
  ChapterLoadState get chapterLoadState => _chapterLoadState;
  bool get isDefaultBookMode => _isDefaultBookMode;
  int? get currentChapterIndex => _currentChapterIndex;

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
    return TextProcessing.cleanChapterTitle(raw);
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
        currentItem.session == _ttsNotifier?.currentSession &&
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

    // 加载非默认书时，强制清除默认书模式残留，避免章末误触 _autoAdvanceChapter
    if (bookId != BookConstants.defaultBookKey) {
      _isDefaultBookMode = false;
      _currentChapterIndex = null;
      _chapterLoadState = ChapterLoadState.idle;
    }

    final Map<int, int> rawLineToSentIdx = {};
    for (int i = 0; i < rawLineOrigins.length; i++) {
      rawLineToSentIdx.putIfAbsent(rawLineOrigins[i], () => i);
    }

    final rawChapters = chapters ?? <ChapterModel>[];
    _chapters = rawChapters.map((c) {
      final cleaned = TextProcessing.cleanChapterTitle(c.title);
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

    // 只有 TTS 正在播放/缓冲时才刷新会话（新章继续播）。
    if (_ttsNotifier?.isActivelyPlaying == true) {
      _ttsNotifier?.refreshSession();
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
    } catch (e, st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'reader',
        extra: {'context': 'ReaderProvider.loadPreparedBook 异常'},
      );
    } finally {
      _isParsing = false;
      notifyListeners();
    }
  }

  /// 核心加载方法：加载书籍并解析
  Future<void> loadBook(
    String rawText, {
    String? bookId,
    List<ChapterModel>? chapters,
    int? initialIndex,
    bool forceIndex = false,
  }) async {
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
    } catch (e, st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'reader',
        extra: {
          'context': 'ReaderProvider.loadBook 异常',
          'bookId': bookId ?? '',
        },
      );
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
    final notifier = _ttsNotifier;
    if (notifier == null) return TtsToggleResult.noContent;
    return switch (_ttsEngine.state) {
      TtsPlaybackState.playing || TtsPlaybackState.buffering => () {
          notifier.pause();
          return TtsToggleResult.paused;
        }(),
      TtsPlaybackState.paused || TtsPlaybackState.disabled => () {
          notifier.play();
          return TtsToggleResult.playing;
        }(),
      TtsPlaybackState.error => () {
          _ttsEngine.clearLastError();
          notifier.play();
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
      _saveProgress().catchError((e) {
        CyberLogger.captureWarning(
          e,
          tag: 'reader',
          extra: {'context': 'nextSentence 进度保存失败'},
        );
      });

      // 仅在 TTS 播放/缓冲时刷新，空闲不启泵
      if (_ttsNotifier?.isActivelyPlaying == true) {
        Future.microtask(() => _ttsNotifier?.refreshSession());
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
      _saveProgress().catchError((e) {
        CyberLogger.captureWarning(
          e,
          tag: 'reader',
          extra: {'context': 'previousSentence 进度保存失败'},
        );
      });

      // 仅在 TTS 播放/缓冲时刷新，空闲不启泵
      if (_ttsNotifier?.isActivelyPlaying == true) {
        Future.microtask(() => _ttsNotifier?.refreshSession());
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
      CyberLogger.captureWarning(
        StateError('jumpTo 越界'),
        tag: 'reader',
        extra: {'index': '$index', 'max': '${_sentences.length - 1}'},
      );
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

    // 🔥 第一时间同步更新，让所有 UI 瞬间响应
    _currentIndex = targetIndex;
    _fetchIndex = targetIndex;
    notifyListeners();

    // Fire-and-forget 存档
    _saveProgress().catchError((e) {
      CyberLogger.captureWarning(
        e,
        tag: 'reader',
        extra: {'context': 'jumpTo 进度保存失败'},
      );
    });

    // 仅在 TTS 播放/缓冲时刷新，空闲不启泵
    if (_ttsNotifier?.isActivelyPlaying == true) {
      Future.microtask(() => _ttsNotifier?.refreshSession());
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
    // 仅在 TTS 播放/缓冲时刷新，空闲不启泵
    if (_ttsNotifier?.isActivelyPlaying == true) {
      _ttsNotifier?.refreshSession();
    }
    notifyListeners();
    _saveProgress().catchError((e) {
      CyberLogger.captureWarning(
        e,
        tag: 'reader',
        extra: {'context': 'switchChapter 进度保存失败'},
      );
    });
  }

  /// 🔥 任务 1.3：级联重置——当当前正在阅读的书籍被删除时，完全重置阅读器状态
  void resetForDeletedBook(String bookId) {
    if (_currentBookId != bookId) return;

    // 停止 TTS 播放（无论是否启用，强制清空缓冲区和泵）
    _ttsNotifier?.stopAll();

    // 置空所有数据
    _currentBookId = null;
    _sentences = [];
    _chapters = [];
    _currentIndex = 0;
    _fetchIndex = 0;

    // 重置分章懒加载模式，防止残留状态触发 _autoAdvanceChapter
    _isDefaultBookMode = false;
    _currentChapterIndex = null;
    _chapterLoadState = ChapterLoadState.idle;

    // 异步清除持久化的当前小说标识
    StorageService.setCurrentNovelId(null)
        .catchError((Object e, StackTrace st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'reader',
        extra: {'context': 'resetForDeletedBook 清除 novelId 持久化失败'},
      );
    });

    notifyListeners();
    CyberLogger.captureMessage(
      '级联重置：书籍 $bookId 已删除，ReaderProvider 已清空',
      tag: 'reader',
    );
  }

  // ── 分章懒加载：核心方法 ──────────────────────────────────────────────────

  /// 加载指定章节（默认书籍模式专用）
  ///
  /// [resume] 为 true 时从上次进度续读（仅第一次启动时传 true），
  /// 切章/章末推进时传 false（从头开始）。
  Future<void> loadChapter(int chapterIndex, {bool resume = false}) async {
    if (chapterIndex < 0 ||
        chapterIndex >= BookConstants.defaultTotalChapters) {
      return;
    }

    _currentChapterIndex = chapterIndex;
    _isDefaultBookMode = true;
    _chapterLoadState = ChapterLoadState.loading;
    notifyListeners();

    try {
      final service = _defaultBookService ??= DefaultBookService();
      final text = await service.fetchChapter(chapterIndex);

      if (text == null) {
        _chapterLoadState = ChapterLoadState.error;
        notifyListeners();
        return;
      }

      await loadBook(
        text,
        bookId: BookConstants.defaultBookKey,
        chapters: [
          ChapterModel(
            title: BookConstants.xiyoujiChapterTitles[chapterIndex],
            lineIndex: 0,
          ),
        ],
        initialIndex: resume ? null : 0,
      );
      _chapterLoadState = ChapterLoadState.loaded;
      // 持久化章节索引，供热重启恢复
      StorageService.setCurrentChapterIndex(chapterIndex);
      // 影子预读下一章（fire-and-forget）
      service.prefetchNextChapter(chapterIndex);
      notifyListeners();
    } catch (e, st) {
      _chapterLoadState = ChapterLoadState.error;
      notifyListeners();
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'reader',
        extra: {'context': 'loadChapter 失败', 'chapterIndex': '$chapterIndex'},
      );
    }
  }

  /// 热重启恢复：自动加载上次章节内容
  void restoreDefaultBook() {
    if (_isDefaultBookMode) return;
    final chapterIndex = StorageService.getCurrentChapterIndex();
    CyberLogger.captureMessage('自动恢复默认书第 $chapterIndex 章', tag: 'reader');
    // 先用常量填充标题，让 UI 立即有内容可显示
    _isDefaultBookMode = true;
    _currentChapterIndex = chapterIndex;
    _chapterLoadState = ChapterLoadState.idle;
    if (_chapters.isEmpty) {
      _chapters = BookConstants.xiyoujiChapterTitles
          .asMap()
          .entries
          .map((e) => ChapterModel(title: e.value, lineIndex: e.key))
          .toList();
    }
    // 恢复 _currentIndex，使章节标题显示正确
    _currentIndex = chapterIndex;
    notifyListeners();
    // 异步加载章节正文，完成后提词器自动更新
    loadChapter(chapterIndex, resume: true);
  }

  /// 章末自动推进（TTS 播完当前章节最后一句时由 [onTtsItemFinished] 触发）
  Future<void> _autoAdvanceChapter() async {
    final nextChapter = (_currentChapterIndex ?? -1) + 1;
    if (nextChapter >= BookConstants.defaultTotalChapters) {
      CyberLogger.captureMessage('已到最后一章，停止自动推进', tag: 'reader');
      return;
    }
    CyberLogger.captureMessage('章末自动推进到第 $nextChapter 章', tag: 'reader');
    await loadChapter(nextChapter, resume: false);
  }

  @override
  void dispose() {
    _ttsEngine.removeListener(_onTtsEngineChanged);
    super.dispose();
  }
}
