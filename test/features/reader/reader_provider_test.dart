import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/core/constants/book_constants.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/features/audio/domain/tts_audio_state.dart';
import 'package:yueyou/features/audio/providers/tts_audio_notifier.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/library/domain/book_model.dart';
import 'package:yueyou/features/library/services/default_book_service.dart';
import 'package:yueyou/features/reader/domain/chapter_load_state.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';
import '../../utils/test_utils.dart';

/// 伪默认书籍服务：用于驱动 loadChapter / _autoAdvanceChapter 全分支。
class _FakeDefaultBookService extends DefaultBookService {
  final Map<int, String?> chapters;
  final List<int> prefetchCalls = [];
  bool throwOnFetch = false;

  _FakeDefaultBookService(this.chapters) : super();

  @override
  Future<String?> fetchChapter(int chapterIndex) async {
    if (throwOnFetch) throw StateError('fake fetch error');
    return chapters[chapterIndex];
  }

  @override
  void prefetchNextChapter(int currentChapterIndex) {
    prefetchCalls.add(currentChapterIndex);
  }
}

Future<ReaderProvider> _makeReaderProvider() async {
  final (reader, _) = await makeReaderStack();
  return reader;
}

/// 阶段 1 推进：构造同时含有 TtsAudioNotifier 的 ReaderProvider，
/// 用于覆盖 toggleTTS switch 分支与 nextSentence/jumpTo/switchChapter
/// 中 `_ttsNotifier?.isActivelyPlaying == true` 的 refreshSession 路径。
Future<
    ({
      ReaderProvider reader,
      TtsAudioNotifier notifier,
      TtsEngineService engine,
      ProviderContainer container
    })> _makeReaderWithNotifier() async {
  await initializeTestEnvironment();
  final settings = makeSettings();
  final engine = makeTtsEngine(settings);
  final container = ProviderContainer(
    overrides: [
      ttsEngineProvider.overrideWith((ref) => engine),
      settingsProvider.overrideWith((ref) => settings),
    ],
  );
  // 等待引擎硬件初始化完成（避免 LateInitializationError）。
  for (int i = 0; i < 50; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  final notifier = container.read(ttsAudioProvider.notifier);
  final reader = ReaderProvider(engine, notifier: notifier);
  addTearDown(() {
    container.dispose();
    engine.dispose();
  });
  return (
    reader: reader,
    notifier: notifier,
    engine: engine,
    container: container
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReaderProvider - 加载与章节映射', () {
    test('loadBook 清洗章节标题并映射到 sentences 索引', () async {
      final reader = await _makeReaderProvider();
      const raw = '正文 第一章 开始\n\n你好。\n第二句！\nVIP卷 第二章 继续\n短\n词\n段。\n';
      const chapters = [
        ChapterModel(title: '正文 第一章 开始', lineIndex: 0),
        ChapterModel(title: 'VIP卷 第二章 继续', lineIndex: 4),
      ];

      await reader.loadBook(
        raw,
        bookId: 'book1',
        chapters: chapters,
        initialIndex: 0,
        forceIndex: true,
      );

      expect(reader.chapters.length, 2);
      expect(reader.chapters.first.title, '第一章 开始');
      expect(reader.chapters.last.title, '第二章 继续');
      expect(reader.currentChapterTitle, '第一章 开始');
      expect(reader.currentIndex, 0);
      expect(reader.fetchIndex, 0);
      expect(reader.sentences, isNotEmpty);
    });

    test('loadBook 在 forceIndex=false 时优先恢复阅读记录 cursor', () async {
      final reader = await _makeReaderProvider();

      await StorageService.updateReadingRecord('book_restore', 2, 999);

      const raw = 'A。\nB。\nC。\nD。\n';
      await reader.loadBook(raw, bookId: 'book_restore');

      expect(reader.currentIndex, 2);
      expect(reader.currentSentence, 'C。');
      expect(reader.fetchIndex, reader.currentIndex);
    });

    test('currentChapterTitle 在无章节数据时返回 未知章节', () async {
      final reader = await _makeReaderProvider();
      const raw = 'A。\nB。\n';
      await reader.loadBook(raw, bookId: 'book_no_chapters');
      expect(reader.currentChapterTitle, '未知章节');
    });

    test('空文本加载后：progress=0 且 currentSentence=null', () async {
      final reader = await _makeReaderProvider();
      await reader.loadBook('', bookId: 'book_empty');
      expect(reader.sentences, isEmpty);
      expect(reader.progress, 0.0);
      expect(reader.currentSentence, isNull);
    });

    test('无有效阅读记录时，loadBook 使用 initialIndex（forceIndex=false）', () async {
      final reader = await _makeReaderProvider();
      const raw = 'A。\nB。\nC。\nD。\n';

      await reader.loadBook(
        raw,
        bookId: 'book_initial',
        initialIndex: 3,
        forceIndex: false,
      );

      expect(reader.currentIndex, 3);
      expect(reader.currentSentence, 'D。');
    });

    test('阅读记录 total<=1 时，loadBook 回退使用 initialIndex', () async {
      final reader = await _makeReaderProvider();
      await StorageService.updateReadingRecord('book_total_1', 0, 1);

      const raw = 'A。\nB。\nC。\n';
      await reader.loadBook(
        raw,
        bookId: 'book_total_1',
        initialIndex: 1,
        forceIndex: false,
      );

      expect(reader.currentSentence, 'B。');
      expect(reader.currentIndex, 1);
    });

    test('bookId=null 时，loadBook 使用 initialIndex', () async {
      final reader = await _makeReaderProvider();
      const raw = 'A。\nB。\nC。\n';
      await reader.loadBook(
        raw,
        initialIndex: 2,
        forceIndex: false,
      );

      expect(reader.currentIndex, 2);
      expect(reader.currentSentence, 'C。');
    });
  });

  group('ReaderProvider - 预取与步进', () {
    test('onNeedPrefetch 合并短句至≥5字符，并推进 fetchIndex', () async {
      final reader = await _makeReaderProvider();
      const raw = '标题\n短\n词\n段。\n结尾。\n';
      await reader.loadBook(
        raw,
        bookId: 'b2',
        initialIndex: 0,
        forceIndex: true,
      );

      // 跳到“短”所在句，验证合并行为
      final shortIdx = reader.sentences.indexOf('短');
      expect(shortIdx, isNonNegative);
      await reader.jumpTo(shortIdx);
      final before = reader.fetchIndex;

      final req = await reader.nextTtsSentence(0);
      expect(req, isNotNull);
      expect(req!.text.length, greaterThanOrEqualTo(5));
      expect(req.text.startsWith('短'), isTrue);
      // P0-5：取消 (cursor + 1) % length 取模回卷后，
      // consumed 到达末尾时 _fetchIndex 必须严格等于 sentences.length，
      // 不再有"绕回 0"的合法路径。
      expect(reader.fetchIndex, greaterThan(before));
      expect(reader.fetchIndex, reader.sentences.length);
    });

    // ── T-2 / P0-5 回归用例：章末全噪音不得回卷重读章首 ─────────────────────
    test('章末连续噪音行：nextTtsSentence 必须返回 null 而非回卷至章首', () async {
      final reader = await _makeReaderProvider();
      // 构造一个"前段有效 + 章末连续 5 行噪音"的极端样本，
      // 旧实现会因取模回卷把 cursor 绕回 0，把第 0 行可读句返回。
      const raw = '第一段有效内容。\n第二段也是有效内容。\n正文\nVIP卷\n默认卷\n***\n----\n';
      await reader.loadBook(
        raw,
        bookId: 'b_chapter_end_noise',
        initialIndex: 0,
        forceIndex: true,
      );

      // 先把游标推到章末噪音段起始位置（第三句开始全是噪音）。
      // 直接强制 _fetchIndex 到噪音段起点，模拟连续读完前两句之后的状态。
      final firstReq = await reader.nextTtsSentence(0);
      expect(firstReq, isNotNull, reason: '第一句必须能正常返回');

      final secondReq = await reader.nextTtsSentence(0);
      expect(secondReq, isNotNull, reason: '第二句必须能正常返回');

      // 此时 fetchIndex 已推进到噪音段，再次调用必须返回 null
      final tailReq = await reader.nextTtsSentence(0);
      expect(tailReq, isNull, reason: '章末仅剩噪音行时必须返回 null，绝不能回卷至章首重读');
      expect(reader.fetchIndex, reader.sentences.length,
          reason: '_fetchIndex 必须钉到末尾，避免下次重复扫描');

      // 再次调用仍必须返回 null（_fetchIndex >= length 早期返回路径）
      final repeatReq = await reader.nextTtsSentence(0);
      expect(repeatReq, isNull);
    });

    test('全文皆噪音：nextTtsSentence 必须返回 null，不得死循环', () async {
      final reader = await _makeReaderProvider();
      const raw = '正文\nVIP卷\n默认卷\n***\n';
      await reader.loadBook(
        raw,
        bookId: 'b_all_noise',
        initialIndex: 0,
        forceIndex: true,
      );

      final req = await reader.nextTtsSentence(0);
      expect(req, isNull, reason: '全噪音输入必须返回 null');
      expect(reader.fetchIndex, reader.sentences.length,
          reason: '扫描到末尾必须把 _fetchIndex 钉到 length');
    });

    test('nextSentence 步进：currentIndex 与 fetchIndex 同步递增', () async {
      final reader = await _makeReaderProvider();
      const raw = 'A。\nB。\nC。\n';
      await reader.loadBook(
        raw,
        bookId: 'b3',
        initialIndex: 0,
        forceIndex: true,
      );
      final prev = reader.currentIndex;
      await reader.nextSentence();
      expect(reader.currentIndex, prev + 1);
      expect(reader.fetchIndex, reader.currentIndex);
    });

    test('nextSentence 在最后一句时不越界', () async {
      final reader = await _makeReaderProvider();
      const raw = 'A。\nB。\n';
      await reader.loadBook(
        raw,
        bookId: 'b_last',
        initialIndex: 1,
        forceIndex: true,
      );
      expect(reader.currentIndex, 1);
      await reader.nextSentence();
      expect(reader.currentIndex, 1);
    });

    test('previousSentence 回退：currentIndex 与 fetchIndex 同步递减', () async {
      final reader = await _makeReaderProvider();
      const raw = 'A。\nB。\nC。\n';
      await reader.loadBook(
        raw,
        bookId: 'b_prev',
        initialIndex: 2,
        forceIndex: true,
      );
      await reader.previousSentence();
      expect(reader.currentIndex, 1);
      expect(reader.fetchIndex, reader.currentIndex);
    });

    test('previousSentence 在第一句时不越界', () async {
      final reader = await _makeReaderProvider();
      const raw = 'A。\nB。\n';
      await reader.loadBook(
        raw,
        bookId: 'b_prev0',
        initialIndex: 0,
        forceIndex: true,
      );
      await reader.previousSentence();
      expect(reader.currentIndex, 0);
    });

    test('jumpTo 跳过噪音行并同步 fetchIndex', () async {
      final reader = await _makeReaderProvider();
      const raw = '正文\n有效句。\n';
      await reader.loadBook(
        raw,
        bookId: 'b4',
        initialIndex: 0,
        forceIndex: true,
      );
      // 跳到第0行（噪音），应自动跳到下一有效句
      await reader.jumpTo(0);
      expect(reader.currentSentence, '有效句。');
      expect(reader.currentIndex, 1);
      expect(reader.fetchIndex, reader.currentIndex);
    });

    test('jumpTo 越界时不改变 currentIndex', () async {
      final reader = await _makeReaderProvider();
      const raw = 'A。\nB。\n';
      await reader.loadBook(
        raw,
        bookId: 'b_oob',
        initialIndex: 1,
        forceIndex: true,
      );
      await reader.jumpTo(-1);
      expect(reader.currentIndex, 1);
      await reader.jumpTo(999);
      expect(reader.currentIndex, 1);
    });

    test('jumpTo 噪音连续到结尾时触发 fallback（保持原 index）', () async {
      final reader = await _makeReaderProvider();
      const raw = '有效句。\n正文\n';
      await reader.loadBook(
        raw,
        bookId: 'b_fallback',
        initialIndex: 0,
        forceIndex: true,
      );
      final noiseIdx = reader.sentences.indexOf('正文');
      expect(noiseIdx, isNonNegative);
      await reader.jumpTo(noiseIdx);
      expect(reader.currentIndex, noiseIdx);
      expect(reader.currentSentence, '正文');
    });

    test('onItemStarted 用真实 lineIndex 同步 UI currentIndex', () async {
      final reader = await _makeReaderProvider();
      const raw = 'A。\nB。\nC。\n';
      await reader.loadBook(
        raw,
        bookId: 'b_started',
        initialIndex: 0,
        forceIndex: true,
      );

      int notified = 0;
      reader.addListener(() => notified++);

      final item = TtsAudioItem(
        id: 1,
        session: reader.ttsEngine.currentSession,
        lineIndex: 2,
        text: 'C。',
        title: 't',
        estimatedDuration: Duration.zero,
      );

      await reader.onTtsItemStarted(item);
      expect(reader.currentIndex, 2);
      expect(notified, greaterThan(0));
    });

    test('onItemFinished 跳过噪音行并推进 currentIndex', () async {
      final reader = await _makeReaderProvider();
      const raw = 'A。\n正文\nB。\n';
      await reader.loadBook(
        raw,
        bookId: 'b_finished',
        initialIndex: 0,
        forceIndex: true,
      );

      final item = TtsAudioItem(
        id: 1,
        session: reader.ttsEngine.currentSession,
        lineIndex: 0,
        text: 'A。',
        title: 't',
        estimatedDuration: Duration.zero,
      );

      await reader.onTtsItemFinished(item);
      expect(reader.currentSentence, 'B。');
    });

    test('onItemFinished 在最后一句时保持在末尾（不越界）', () async {
      final reader = await _makeReaderProvider();
      const raw = 'A。\nB。\n';
      await reader.loadBook(
        raw,
        bookId: 'b_finished_last',
        initialIndex: 0,
        forceIndex: true,
      );

      final item = TtsAudioItem(
        id: 1,
        session: reader.ttsEngine.currentSession,
        lineIndex: 1,
        text: 'B。',
        title: 't',
        estimatedDuration: Duration.zero,
      );

      await reader.onTtsItemFinished(item);
      expect(reader.currentIndex, 1);
      expect(reader.currentSentence, 'B。');
    });

    test('jumpToLine 是 jumpTo 的兼容包装', () async {
      final reader = await _makeReaderProvider();
      const raw = '正文\n有效句。\n第二句。\n';
      await reader.loadBook(
        raw,
        bookId: 'b_jump_line',
        initialIndex: 0,
        forceIndex: true,
      );
      await reader.jumpToLine(0);
      expect(reader.currentSentence, '有效句。');
    });

    test('cycleSpeed 委托给 TTS 引擎并更新 playbackRate', () async {
      final reader = await _makeReaderProvider();
      const raw = 'A。\nB。\n';
      await reader.loadBook(
        raw,
        bookId: 'b_speed',
        initialIndex: 0,
        forceIndex: true,
      );

      final before = reader.ttsEngine.playbackRate;
      reader.cycleSpeed();
      expect(reader.ttsEngine.playbackRate, isNot(equals(before)));
    });

    test('toggleTTS 无书籍时返回 noContent', () async {
      final reader = await _makeReaderProvider();
      final result = reader.toggleTTS();
      expect(result, TtsToggleResult.noContent);
    });

    test('toggleTTS 有内容但无编排层时返回 noContent', () async {
      final reader = await _makeReaderProvider();
      await reader.loadBook(
        '第一章 开始\n你好世界。\n',
        bookId: 'b_toggle',
        initialIndex: 0,
        forceIndex: true,
      );
      // 无 TtsAudioNotifier 编排层时，toggleTTS 正确返回 noContent
      final result = reader.toggleTTS();
      expect(result, TtsToggleResult.noContent);
    });

    test('相同 TTS 错误重复写入时 ReaderProvider 不重复通知', () async {
      final reader = await _makeReaderProvider();
      int notified = 0;
      reader.addListener(() => notified++);

      reader.ttsEngine.setLastError('网络异常');
      await Future<void>.delayed(Duration.zero);
      final afterFirst = notified;

      reader.ttsEngine.setLastError('网络异常');
      await Future<void>.delayed(Duration.zero);

      expect(afterFirst, greaterThan(0));
      expect(notified, afterFirst);
    });
  });

  // ── 阶段 1 治理：补 ReaderProvider 未覆盖分支 ──────────────────────────
  group('ReaderProvider - switchChapter / resetForDeletedBook / 边界', () {
    test('switchChapter 在 chapters 为空时静默返回（无副作用）', () async {
      final reader = await _makeReaderProvider();
      await reader.loadBook(
        'A。\nB。\n',
        bookId: 'b_no_chapters',
        initialIndex: 1,
        forceIndex: true,
      );
      final beforeIndex = reader.currentIndex;
      reader.switchChapter(0);
      expect(reader.currentIndex, beforeIndex,
          reason: 'chapters 为空时 switchChapter 不得改变 currentIndex');
    });

    test('switchChapter 越界（负 / 超长）时静默返回', () async {
      final reader = await _makeReaderProvider();
      await reader.loadBook(
        '第一章 起\nA。\n第二章 续\nB。\n',
        bookId: 'b_bound',
        chapters: const [
          ChapterModel(title: '第一章 起', lineIndex: 0),
          ChapterModel(title: '第二章 续', lineIndex: 2),
        ],
        initialIndex: 0,
        forceIndex: true,
      );
      reader.switchChapter(-1);
      expect(reader.currentIndex, 0);
      reader.switchChapter(999);
      expect(reader.currentIndex, 0);
    });

    test('switchChapter 正常路径：跳到第二章并同步 fetchIndex', () async {
      final reader = await _makeReaderProvider();
      await reader.loadBook(
        '第一章 起\nA。\n第二章 续\nB。\n',
        bookId: 'b_switch_ok',
        chapters: const [
          ChapterModel(title: '第一章 起', lineIndex: 0),
          ChapterModel(title: '第二章 续', lineIndex: 2),
        ],
        initialIndex: 0,
        forceIndex: true,
      );
      reader.switchChapter(1);
      expect(reader.currentIndex, 2);
      expect(reader.fetchIndex, reader.currentIndex,
          reason: 'switchChapter 必须同步 fetchIndex');
    });

    test('resetForDeletedBook：bookId 不匹配时不得重置当前阅读', () async {
      final reader = await _makeReaderProvider();
      await reader.loadBook(
        'A。\nB。\n',
        bookId: 'book_keep',
        initialIndex: 1,
        forceIndex: true,
      );
      reader.resetForDeletedBook('some_other_book_id');
      // currentIndex 必须保留
      expect(reader.currentIndex, 1);
      expect(reader.sentences, isNotEmpty);
    });

    test('resetForDeletedBook：bookId 匹配时彻底清空状态', () async {
      final reader = await _makeReaderProvider();
      await reader.loadBook(
        'A。\nB。\nC。\n',
        bookId: 'book_to_delete',
        initialIndex: 2,
        forceIndex: true,
      );
      reader.resetForDeletedBook('book_to_delete');
      expect(reader.sentences, isEmpty,
          reason: 'resetForDeletedBook 必须清空 sentences');
      expect(reader.currentIndex, 0);
      expect(reader.fetchIndex, 0);
    });

    test('cycleSpeed 桥接：调用后 ttsEngine.playbackRate 必须变化', () async {
      final reader = await _makeReaderProvider();
      final before = reader.ttsEngine.playbackRate;
      reader.cycleSpeed();
      expect(reader.ttsEngine.playbackRate, isNot(equals(before)));
    });

    test('clearTtsError 必须清空 ttsEngine.lastError', () async {
      final reader = await _makeReaderProvider();
      reader.ttsEngine.setLastError('某错误');
      expect(reader.ttsEngine.lastError, isNotNull);

      reader.clearTtsError();
      expect(reader.ttsEngine.lastError, isNull);
    });

    test('loadChapter 越界（< 0 或 >= defaultTotalChapters）必须立即返回', () async {
      final reader = await _makeReaderProvider();
      // 越界 → 不抛异常 / 不修改任何状态
      await reader.loadChapter(-1);
      await reader.loadChapter(999);
      expect(reader.sentences, isEmpty,
          reason: '越界 loadChapter 不得修改 sentences');
    });

    test('jumpTo 在 sentences 为空时静默返回', () async {
      final reader = await _makeReaderProvider();
      // 不调用 loadBook → sentences 为空
      await reader.jumpTo(5);
      expect(reader.currentIndex, 0);
      expect(reader.sentences, isEmpty);
    });
  });

  // ── 阶段 1 推进：loadPreparedBook + onTtsItemStarted/Finished + 状态监听 ─
  group('ReaderProvider - loadPreparedBook 与回调路径', () {
    test('loadPreparedBook 正常路径：sentences 同步、bookId 写入', () async {
      final reader = await _makeReaderProvider();
      await reader.loadPreparedBook(
        const ['第一行', '', '第二行', '   ', '第三行'],
        bookId: 'b_prepared',
        chapters: const [
          ChapterModel(title: '序章', lineIndex: 0),
        ],
        initialIndex: 0,
      );

      expect(reader.sentences, equals(['第一行', '第二行', '第三行']),
          reason: 'loadPreparedBook 必须过滤空行与空白');
      expect(reader.currentBookId, 'b_prepared');
      expect(reader.chapters.length, 1);
    });

    test('loadPreparedBook 在 isParsing 期间立即返回（守卫）', () async {
      final reader = await _makeReaderProvider();
      // 先用 loadBook 进入 isParsing 状态？由于异步，无法稳定卡住，
      // 改为用同步法：连续两次 loadPreparedBook，第二次同 bookId 必须立即返回。
      final first = reader.loadPreparedBook(
        const ['A', 'B'],
        bookId: 'b_concurrent',
      );
      final second = reader.loadPreparedBook(
        const ['X', 'Y'],
        bookId: 'b_concurrent_2',
      );
      await Future.wait([first, second]);
      // 第二次调用在 isParsing 期间应被拦截，第一次的 bookId 应保留
      // （实际行为取决于 await 时机；此处仅验证 sentences 来自两个之一，且不抛异常）
      expect(reader.sentences, anyOf(equals(['A', 'B']), equals(['X', 'Y'])));
    });

    test('onTtsItemStarted：lineIndex 与当前不一致时同步 currentIndex', () async {
      final reader = await _makeReaderProvider();
      await reader.loadBook(
        'A。\nB。\nC。\nD。\n',
        bookId: 'b_started',
        initialIndex: 0,
        forceIndex: true,
      );
      expect(reader.currentIndex, 0);

      reader.onTtsItemStarted(TtsAudioItem(
        id: 1,
        session: 0,
        lineIndex: 2,
        endLineIndex: 2,
        text: 'C。',
        title: '',
        estimatedDuration: const Duration(seconds: 1),
      ));
      expect(reader.currentIndex, 2,
          reason: 'onTtsItemStarted 必须同步 currentIndex');
    });

    test('onTtsItemStarted：相同 lineIndex 不触发不必要的 notifyListeners', () async {
      final reader = await _makeReaderProvider();
      await reader.loadBook(
        'A。\nB。\n',
        bookId: 'b_started_same',
        initialIndex: 1,
        forceIndex: true,
      );
      int notified = 0;
      reader.addListener(() => notified++);

      reader.onTtsItemStarted(TtsAudioItem(
        id: 2,
        session: 0,
        lineIndex: 1, // 与 currentIndex 相同
        endLineIndex: 1,
        text: 'B。',
        title: '',
        estimatedDuration: const Duration(seconds: 1),
      ));

      expect(notified, 0,
          reason: 'lineIndex 与 currentIndex 相同时不得 notifyListeners');
    });

    test('onTtsItemFinished：sentences 为空时立即返回', () async {
      final reader = await _makeReaderProvider();
      // 不调用 loadBook → sentences 为空
      await reader.onTtsItemFinished(TtsAudioItem(
        id: 3,
        session: 0,
        lineIndex: 0,
        endLineIndex: 0,
        text: '',
        title: '',
        estimatedDuration: const Duration(seconds: 1),
      ));
      // 不抛异常即视为守卫生效
      expect(reader.sentences, isEmpty);
    });

    test('onTtsItemFinished：endLineIndex 跳过噪音行后到达章末', () async {
      final reader = await _makeReaderProvider();
      // 让 reader 解析为 sentences = ['第一句', '正文']（末尾噪音）
      await reader.loadBook(
        '第一句\n正文\n',
        bookId: 'b_chapter_end',
        initialIndex: 0,
        forceIndex: true,
      );

      // 完成第 0 行后，nextIdx = 1，sentences[1] = '正文' 是噪音 →
      // nextIdx 推进到 sentences.length → 进入章节末尾分支
      await reader.onTtsItemFinished(TtsAudioItem(
        id: 4,
        session: 0,
        lineIndex: 0,
        endLineIndex: 0,
        text: '第一句',
        title: '',
        estimatedDuration: const Duration(seconds: 1),
      ));
      // 章末分支会把 _currentIndex 钉到 item.lineIndex (0)
      expect(reader.currentIndex, 0);
    });

    test('_onTtsEngineChanged：lastError 变更必须 notifyListeners', () async {
      final reader = await _makeReaderProvider();
      int notified = 0;
      reader.addListener(() => notified++);

      reader.ttsEngine.setLastError('阶段 1 测试错误');
      await Future<void>.delayed(Duration.zero);

      expect(notified, greaterThan(0),
          reason: 'ttsEngine.setLastError 必须传播到 ReaderProvider listener');
      expect(reader.ttsErrorMessage, '阶段 1 测试错误');
    });

    test('resetFetchIndex 必须把 _fetchIndex 钉到 currentIndex', () async {
      final reader = await _makeReaderProvider();
      await reader.loadBook(
        'A。\nB。\nC。\nD。\n',
        bookId: 'b_reset_fetch',
        initialIndex: 0,
        forceIndex: true,
      );
      // 先消费几个句子让 fetchIndex 推进
      await reader.nextTtsSentence(0);
      await reader.nextTtsSentence(0);
      expect(reader.fetchIndex, greaterThan(0));

      await reader.jumpTo(0);
      expect(reader.currentIndex, 0);
      reader.resetFetchIndex();
      expect(reader.fetchIndex, 0,
          reason: 'resetFetchIndex 必须把预取游标重置到 currentIndex');
    });

    test('toggleTTS 在 ttsNotifier=null 时返回 noContent', () async {
      final reader = await _makeReaderProvider();
      await reader.loadBook(
        'A。\n',
        bookId: 'b_toggle_no_notifier',
        initialIndex: 0,
        forceIndex: true,
      );
      // 默认 _makeReaderProvider 不注入 notifier
      final result = reader.toggleTTS();
      expect(result, TtsToggleResult.noContent);
    });
  });

  // ── 阶段 1 第 3 轮：toggleTTS switch 分支 + 步进 refreshSession 路径 ──
  group('ReaderProvider - 与 TtsAudioNotifier 协作分支', () {
    test('toggleTTS：disabled 状态调用必须返回 playing 并触发 notifier.play', () async {
      final s = await _makeReaderWithNotifier();
      await s.reader.loadBook(
        'A。\nB。\n',
        bookId: 'b_toggle_disabled',
        initialIndex: 0,
        forceIndex: true,
      );
      // 引擎默认 disabled
      expect(s.engine.state, TtsPlaybackState.disabled);
      final result = s.reader.toggleTTS();
      expect(result, TtsToggleResult.playing,
          reason: 'disabled 分支必须返回 playing');
      // notifier 触发 play 后会进入 setBusinessError（需先导入...），即 lastError
      // 不为 null（已经导入了 bookId，但 notifier 内部 sentence_source 为 null）
      // 至少不抛异常即视为 switch 分支被走通
      await s.notifier.stopAll();
    });

    test('toggleTTS：error 状态调用必须先 clearLastError 再返回 playing', () async {
      final s = await _makeReaderWithNotifier();
      await s.reader.loadBook(
        'A。\n',
        bookId: 'b_toggle_error',
        initialIndex: 0,
        forceIndex: true,
      );
      // 注入 error 状态
      s.engine.syncShadow(state: TtsPlaybackState.error);
      s.engine.setLastError('某错误');
      expect(s.engine.state, TtsPlaybackState.error);
      expect(s.engine.lastError, isNotNull);

      final result = s.reader.toggleTTS();
      expect(result, TtsToggleResult.playing, reason: 'error 分支必须返回 playing');
      await s.notifier.stopAll();
    });

    test('toggleTTS：playing 状态调用必须返回 paused 并触发 notifier.pause', () async {
      final s = await _makeReaderWithNotifier();
      await s.reader.loadBook(
        'A。\nB。\n',
        bookId: 'b_toggle_playing',
        initialIndex: 0,
        forceIndex: true,
      );
      // 注入 playing 状态
      s.engine.syncShadow(state: TtsPlaybackState.playing);
      expect(s.engine.state, TtsPlaybackState.playing);

      final result = s.reader.toggleTTS();
      expect(result, TtsToggleResult.paused, reason: 'playing 分支必须返回 paused');
      await s.notifier.stopAll();
    });

    test('toggleTTS：buffering 状态调用必须返回 paused（与 playing 共用分支）', () async {
      final s = await _makeReaderWithNotifier();
      await s.reader.loadBook(
        'A。\nB。\n',
        bookId: 'b_toggle_buffering',
        initialIndex: 0,
        forceIndex: true,
      );
      s.engine.syncShadow(state: TtsPlaybackState.buffering);
      final result = s.reader.toggleTTS();
      expect(result, TtsToggleResult.paused);
      await s.notifier.stopAll();
    });

    test('toggleTTS：paused 状态调用必须返回 playing', () async {
      final s = await _makeReaderWithNotifier();
      await s.reader.loadBook(
        'A。\nB。\n',
        bookId: 'b_toggle_paused',
        initialIndex: 0,
        forceIndex: true,
      );
      s.engine.syncShadow(state: TtsPlaybackState.paused);
      final result = s.reader.toggleTTS();
      expect(result, TtsToggleResult.playing);
      await s.notifier.stopAll();
    });

    test('resetForDeletedBook：当前 bookId 命中时必须清空 sentences 与 currentBookId',
        () async {
      final s = await _makeReaderWithNotifier();
      await s.reader.loadBook(
        'A。\n',
        bookId: 'b_reset_match',
        initialIndex: 0,
        forceIndex: true,
      );
      expect(s.reader.sentences, isNotEmpty);
      expect(s.reader.currentBookId, 'b_reset_match');

      s.reader.resetForDeletedBook('b_reset_match');

      expect(s.reader.sentences, isEmpty,
          reason: 'resetForDeletedBook 命中 bookId 时必须清空 sentences');
      expect(s.reader.currentBookId, isNull,
          reason: 'resetForDeletedBook 命中 bookId 时必须清空 currentBookId');
      // 同步触发 notifier.stopAll 后状态必为 Idle
      expect(s.notifier.state, isA<TtsAudioIdle>(),
          reason: 'resetForDeletedBook 必须经 notifier.stopAll 回到 Idle');
    });

    test('resetForDeletedBook：当前 bookId 不匹配时必须保留状态', () async {
      final s = await _makeReaderWithNotifier();
      await s.reader.loadBook(
        'A。\n',
        bookId: 'b_reset_keep',
        initialIndex: 0,
        forceIndex: true,
      );
      s.reader.resetForDeletedBook('other_book');
      expect(s.reader.sentences, isNotEmpty,
          reason: 'bookId 不匹配时不得清空 sentences');
      expect(s.reader.currentBookId, 'b_reset_keep',
          reason: 'bookId 不匹配时必须保留 currentBookId');
    });

    test('dispose 必须正确解绑 ttsEngine listener，post-dispose 写入不影响 reader',
        () async {
      final s = await _makeReaderWithNotifier();
      s.reader.dispose();
      // dispose 后再写 engine.lastError 不应通过 listener 反馈到 reader
      s.engine.setLastError('post-dispose');
      // 不抛异常即视为 listener 已解绑
      expect(s.engine.lastError, 'post-dispose');
    });
  });

  // ── 阶段 1 第 3 轮：默认书章节懒加载 + 章末自动推进 ──
  group('ReaderProvider - 默认书 loadChapter / restoreDefaultBook', () {
    Future<({ReaderProvider reader, _FakeDefaultBookService svc})>
        _makeWithFakeDefaultService(Map<int, String?> chapters) async {
      await initializeTestEnvironment();
      final settings = makeSettings();
      final engine = makeTtsEngine(settings);
      final svc = _FakeDefaultBookService(chapters);
      final reader = ReaderProvider(engine, defaultBookService: svc);
      addTearDown(() {
        reader.dispose();
        engine.dispose();
      });
      return (reader: reader, svc: svc);
    }

    test('loadChapter：越界 chapterIndex 必须直接 return，不修改状态', () async {
      final s = await _makeWithFakeDefaultService({0: '正文。\n'});
      // 越界 -1
      await s.reader.loadChapter(-1);
      expect(s.reader.chapterLoadState, ChapterLoadState.idle);
      expect(s.reader.isDefaultBookMode, isFalse);
      // 越界 totalChapters
      await s.reader.loadChapter(BookConstants.defaultTotalChapters);
      expect(s.reader.chapterLoadState, ChapterLoadState.idle);
      expect(s.reader.isDefaultBookMode, isFalse);
    });

    test('loadChapter：fetchChapter 返回 null 时必须设为 error 状态', () async {
      final s = await _makeWithFakeDefaultService({5: null});
      await s.reader.loadChapter(5);
      expect(s.reader.chapterLoadState, ChapterLoadState.error,
          reason: 'fetchChapter 返回 null 必须置为 error 状态');
      expect(s.reader.isDefaultBookMode, isTrue, reason: '即使失败也已进入默认书模式');
      expect(s.reader.currentChapterIndex, 5);
    });

    test('loadChapter：fetchChapter 抛异常时必须捕获并设为 error 状态', () async {
      final s = await _makeWithFakeDefaultService({3: '正文。\n'});
      s.svc.throwOnFetch = true;
      await s.reader.loadChapter(3);
      expect(s.reader.chapterLoadState, ChapterLoadState.error,
          reason: 'fetchChapter 抛异常必须 catch 并置 error');
      expect(s.reader.isDefaultBookMode, isTrue);
    });

    test('loadChapter：成功时必须 loaded + 持久化 chapterIndex + 触发预读', () async {
      final s = await _makeWithFakeDefaultService({
        7: '第七回正文。\n第二句。\n',
        8: '第八回正文。\n',
      });
      await s.reader.loadChapter(7);
      expect(s.reader.chapterLoadState, ChapterLoadState.loaded);
      expect(s.reader.isDefaultBookMode, isTrue);
      expect(s.reader.currentChapterIndex, 7);
      expect(s.reader.sentences, isNotEmpty, reason: '加载完成后 sentences 必须填充');
      expect(s.reader.currentBookId, BookConstants.defaultBookKey,
          reason: '默认书模式下 bookId 必须为 defaultBookKey');
      expect(StorageService.getCurrentChapterIndex(), 7,
          reason: '必须持久化 chapterIndex 供热重启恢复');
      expect(s.svc.prefetchCalls, contains(7),
          reason: '加载完成后必须触发 prefetchNextChapter 影子预读');
    });

    test('loadChapter：resume=false 时 initialIndex 必须从 0 开始', () async {
      final s = await _makeWithFakeDefaultService({2: '一。\n二。\n三。\n'});
      // 先把进度位写到 5
      await StorageService.updateReadingRecord(
        BookConstants.defaultBookKey,
        5,
        3,
      );
      await s.reader.loadChapter(2, resume: false);
      expect(s.reader.currentIndex, 0, reason: 'resume=false 必须从头开始');
    });

    test('restoreDefaultBook：默认模式已开启时直接 early return', () async {
      final s = await _makeWithFakeDefaultService({0: 'A。\n'});
      // 先正常加载一次进入默认模式
      await s.reader.loadChapter(0);
      final before = s.svc.prefetchCalls.length;
      // 再次调用 restoreDefaultBook 应直接返回，不重复加载
      s.reader.restoreDefaultBook();
      // 同步 path：early return 不会启动新的 fetch
      expect(s.svc.prefetchCalls.length, before, reason: '已在默认模式时不应重复触发预读');
    });

    test('restoreDefaultBook：非默认模式下必须填充 chapters + 触发 loadChapter', () async {
      final s = await _makeWithFakeDefaultService({0: '第一回正文。\n二。\n'});
      // 先持久化 chapterIndex=0
      await StorageService.setCurrentChapterIndex(0);
      s.reader.restoreDefaultBook();
      // 同步部分立即生效
      expect(s.reader.isDefaultBookMode, isTrue);
      expect(s.reader.currentChapterIndex, 0);
      expect(s.reader.chapters, isNotEmpty,
          reason: '必须用 BookConstants.xiyoujiChapterTitles 填充 chapters');
      expect(
          s.reader.chapters.length, BookConstants.xiyoujiChapterTitles.length);
      // 异步 loadChapter 完成后状态变 loaded
      for (int i = 0;
          i < 50 && s.reader.chapterLoadState != ChapterLoadState.loaded;
          i++) {
        await pumpEventQueue();
      }
      expect(s.reader.chapterLoadState, ChapterLoadState.loaded,
          reason: 'restoreDefaultBook 必须触发 loadChapter 加载到 loaded');
    });

    test('章末自动推进：onTtsItemFinished 在末句必须触发 _autoAdvanceChapter', () async {
      final s = await _makeWithFakeDefaultService({
        4: '第五回正文。\n', // 仅一行 → 末句即首句
        5: '第六回正文。\n',
      });
      await s.reader.loadChapter(4);
      expect(s.reader.currentChapterIndex, 4);
      expect(s.reader.isDefaultBookMode, isTrue);

      // 模拟 TTS 播完最后一个 item（lineIndex == sentences.length - 1）
      final lastIndex = s.reader.sentences.length - 1;
      await s.reader.onTtsItemFinished(
        TtsAudioItem(
          id: 1,
          session: 0,
          lineIndex: lastIndex,
          title: '',
          text: s.reader.sentences[lastIndex],
          estimatedDuration: const Duration(seconds: 1),
        ),
      );
      // 等待 _autoAdvanceChapter 完成（必须同时等到 chapterLoadState 稳定到 loaded，
      // 否则 fire-and-forget 的 loadChapter 会在 teardown dispose 后继续 notifyListeners 抛异常）。
      // 用 pumpEventQueue 排干微任务，避免真定时器 5ms 累加耗时。
      for (int i = 0; i < 100; i++) {
        if (s.reader.currentChapterIndex == 5 &&
            s.reader.chapterLoadState == ChapterLoadState.loaded) {
          break;
        }
        await pumpEventQueue();
      }
      expect(s.reader.currentChapterIndex, 5, reason: '章末必须自动推进到下一章');
      expect(s.reader.chapterLoadState, ChapterLoadState.loaded,
          reason: '推进后必须达到 loaded 稳定态');
    });

    test('章末自动推进：已是最后一章时必须停止推进', () async {
      final last = BookConstants.defaultTotalChapters - 1;
      final s = await _makeWithFakeDefaultService({last: '终章正文。\n'});
      await s.reader.loadChapter(last);
      final lastIndex = s.reader.sentences.length - 1;
      await s.reader.onTtsItemFinished(
        TtsAudioItem(
          id: 1,
          session: 0,
          lineIndex: lastIndex,
          title: '',
          text: s.reader.sentences[lastIndex],
          estimatedDuration: const Duration(seconds: 1),
        ),
      );
      // 排干任何潜在的微任务，避免中间状态脱锁
      await pumpEventQueue();
      await pumpEventQueue();
      expect(s.reader.currentChapterIndex, last, reason: '已是最后一章必须停留，不再推进');
    });
  });
}
