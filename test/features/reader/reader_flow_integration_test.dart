import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/features/audio/domain/tts_audio_state.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/library/domain/book_model.dart';
import 'package:yueyou/features/reader/domain/text_parser.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import '../../utils/test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ReaderProvider, TtsEngineService)> makeStack() =>
      makeReaderStack(parseBook: (raw) async => TextParser.parse(raw));

  group('听书集成 - ReaderProvider 初始状态', () {
    test('初始 sentences 为空', () async {
      final (reader, tts) = await makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });
      expect(reader.sentences, isEmpty);
    });

    test('初始 currentIndex 为 0', () async {
      final (reader, tts) = await makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });
      expect(reader.currentIndex, 0);
    });

    test('初始 isParsing 为 false', () async {
      final (reader, tts) = await makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });
      expect(reader.isParsing, isFalse);
    });
  });

  group('听书集成 - 书籍加载流程', () {
    test('loadBook 后 sentences 非空', () async {
      final (reader, tts) = await makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });
      await reader.loadBook('第一句话。第二句话。第三句话。', bookId: 'b1');
      expect(reader.sentences, isNotEmpty);
      expect(reader.currentBookId, 'b1');
    });

    test('loadBook 解析完成后 isParsing 恢复为 false', () async {
      final (reader, tts) = await makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });
      await reader.loadBook('内容测试句子。', bookId: 'b2');
      expect(reader.isParsing, isFalse);
    });

    test('loadBook 中文标点正确切分句子', () async {
      final (reader, tts) = await makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });
      await reader.loadBook('第一句。第二句！第三句？', bookId: 'b3');
      expect(reader.sentences.length, 3);
    });

    test('loadPreparedBook 直接加载已切分行', () async {
      final (reader, tts) = await makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });
      await reader.loadPreparedBook(
        ['行一内容。', '行二内容。', '行三内容。'],
        bookId: 'prepared_1',
      );
      expect(reader.sentences, hasLength(3));
      expect(reader.currentBookId, 'prepared_1');
    });

    test('loadBook 空文本不崩溃', () async {
      final (reader, tts) = await makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });
      await reader.loadBook('', bookId: 'empty_1');
      expect(reader.sentences, isEmpty);
      expect(reader.isParsing, isFalse);
    });
  });

  group('听书集成 - 进度导航流程', () {
    test('nextSentence 推进 currentIndex', () async {
      final (reader, tts) = await makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });
      await reader.loadBook('第一句。第二句。第三句。', bookId: 'nav_1');
      expect(reader.currentIndex, 0);
      await reader.nextSentence();
      expect(reader.currentIndex, 1);
    });

    test('previousSentence 回退 currentIndex', () async {
      final (reader, tts) = await makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });
      await reader.loadBook('第一句。第二句。第三句。', bookId: 'nav_2');
      await reader.nextSentence();
      expect(reader.currentIndex, 1);
      await reader.previousSentence();
      expect(reader.currentIndex, 0);
    });

    test('currentIndex 不越过 0（previousSentence 在首句无效）', () async {
      final (reader, tts) = await makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });
      await reader.loadBook('只有一句。', bookId: 'nav_3');
      await reader.previousSentence();
      expect(reader.currentIndex, 0);
    });

    test('jumpTo 边界索引不崩溃', () async {
      final (reader, tts) = await makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });
      await reader.loadBook('第一句。第二句。', bookId: 'nav_4');
      await reader.jumpTo(-1);
      await reader.jumpTo(9999);
      expect(reader.currentIndex, isNonNegative);
    });

    test('jumpTo 合法 index 跳转', () async {
      final (reader, tts) = await makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });
      await reader.loadBook('第一句。第二句。第三句。', bookId: 'nav_5');
      await reader.jumpTo(2);
      expect(reader.currentIndex, 2);
    });
  });

  group('听书集成 - 章节加载与切换', () {
    test('带章节的书籍正确挂载章节列表', () async {
      final (reader, tts) = await makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });
      await reader.loadPreparedBook(
        ['第一章 开始', '第一章内容。', '第二章 继续', '第二章内容。'],
        bookId: 'chapter_1',
        chapters: [
          const ChapterModel(title: '第一章 开始', lineIndex: 0),
          const ChapterModel(title: '第二章 继续', lineIndex: 2),
        ],
      );
      expect(reader.chapters, hasLength(2));
    });

    test('switchChapter 跳转到指定章节首行', () async {
      final (reader, tts) = await makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });
      await reader.loadPreparedBook(
        ['第一章内容。', '第二章内容。'],
        bookId: 'chapter_2',
        chapters: [
          const ChapterModel(title: '第一章', lineIndex: 0),
          const ChapterModel(title: '第二章', lineIndex: 1),
        ],
      );
      reader.switchChapter(1);
      expect(reader.currentIndex, 1);
    });
  });

  group('听书集成 - TTS 切换流程', () {
    test('无书籍时 toggleTTS 返回 noContent', () async {
      final (reader, tts) = await makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });
      expect(reader.toggleTTS(), TtsToggleResult.noContent);
    });

    test('有书籍但无编排层时 toggleTTS 返回 noContent', () async {
      final (reader, tts) = await makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });
      await reader.loadBook('播放测试句子。', bookId: 'tts_1');
      expect(reader.toggleTTS(), TtsToggleResult.noContent);
    });

    test('书籍删除后 resetForDeletedBook 清空所有数据', () async {
      final (reader, tts) = await makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });
      await reader.loadBook('测试书籍内容。', bookId: 'del_1');
      expect(reader.sentences, isNotEmpty);
      await reader.resetForDeletedBook('del_1');
      expect(reader.sentences, isEmpty);
      expect(reader.currentBookId, isNull);
      expect(reader.currentIndex, 0);
    });

    test('resetForDeletedBook 对不同 bookId 不产生影响', () async {
      final (reader, tts) = await makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });
      await reader.loadBook('保留的书籍内容。', bookId: 'keep_1');
      await reader.resetForDeletedBook('other_book');
      expect(reader.sentences, isNotEmpty);
      expect(reader.currentBookId, 'keep_1');
    });
  });

  group('听书集成 - 进度持久化', () {
    test('播放完成最后一句后进入完本进度', () async {
      final (reader, tts) = await makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });
      await reader.loadBook(
        '第一句。最后一句。',
        bookId: 'complete_1',
        initialIndex: 0,
        forceIndex: true,
      );

      final lastIndex = reader.sentences.length - 1;
      await reader.onTtsItemFinished(
        TtsAudioItem(
          id: 1,
          session: tts.currentSession,
          lineIndex: lastIndex,
          endLineIndex: lastIndex,
          text: reader.sentences[lastIndex],
          title: '末章',
          estimatedDuration: Duration.zero,
        ),
      );
      await pumpEventQueue();

      expect(reader.currentIndex, lastIndex);
      expect(reader.progress, 1.0, reason: '最后一句完成后首页必须可投影为 completed');
      expect(StorageService.getReadingRecord('complete_1')['percent'], 100.0);
    });

    test('nextSentence 后进度可以通过 StorageService 读取', () async {
      final (reader, tts) = await makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });
      await reader.loadBook('第一句。第二句。第三句。', bookId: 'progress_1');
      await reader.nextSentence();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final record = StorageService.getReadingRecord('progress_1');
      expect(record['cursor'], 1);
    });
  });
}
