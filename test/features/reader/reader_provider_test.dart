import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/library/domain/book_model.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import '../../utils/test_utils.dart';

Future<ReaderProvider> _makeReaderProvider() async {
  final (reader, _) = await makeReaderStack();
  return reader;
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
      // 当 consumed 正好到达末尾时，内部会将 fetchIndex 取模为 0
      expect(reader.fetchIndex, anyOf(greaterThan(before), equals(0)));
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
}
