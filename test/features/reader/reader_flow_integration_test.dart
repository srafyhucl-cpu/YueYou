import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/config/tts_config.dart' as config;
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/library/domain/book_model.dart';
import 'package:yueyou/features/reader/domain/text_parser.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';

// ── Fake 依赖（复用 teleprompter_view_test 里的模式）────────────────────────────

class _FakeHttpClient implements TtsHttpClient {
  final TtsHttpResponse response;
  int requestCount = 0;

  _FakeHttpClient(this.response);

  @override
  Future<TtsHttpResponse> post(Uri url,
      {Map<String, String>? headers, Object? body}) async {
    requestCount++;
    return response;
  }

  @override
  Future<void> download(Uri url, String savePath) async {}
}

class _FakeAudioPlayer implements TtsAudioPlayer {
  @override
  Future<void> setSource(Source source) async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setPlaybackRate(double rate) async {}

  @override
  Stream<void> get onPlayerComplete => const Stream<void>.empty();

  @override
  Future<void> dispose() async {}
}

class _FakeWakeLock implements TtsWakeLock {
  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}
}

// ── 测试工厂函数 ──────────────────────────────────────────────────────────────

Future<(ReaderProvider, TtsEngineService)> _makeStack({
  TtsHttpClient? httpClient,
}) async {
  SharedPreferences.setMockInitialValues({});
  StorageService.resetForTesting();
  await StorageService.init();

  // Mock audioplayers channel
  const MethodChannel global = MethodChannel('xyz.luan/audioplayers.global');
  const MethodChannel player = MethodChannel('xyz.luan/audioplayers');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(global, (MethodCall call) async => null);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(player, (MethodCall call) async => null);

  final settings = SettingsProvider();
  settings.loadFromStorage();
  settings.storyTts = false; // 关闭 TTS 引擎，仅测试解析/加载流程

  final ttsEngine = TtsEngineService(
    settings,
    config: const config.TtsConfig(serverUrl: 'http://test.com/tts'),
    audioPlayer: _FakeAudioPlayer(),
    wakeLock: _FakeWakeLock(),
    httpClient: httpClient ??
        _FakeHttpClient(const TtsHttpResponse(
            statusCode: 200,
            body:
                '{"status": "success", "url": "https://example.com/audio.mp3"}')),
    delayFn: (d) => Future<void>.delayed(Duration.zero),
  );

  // 同步解析（不依赖 Isolate），加速测试
  final reader = ReaderProvider(
    ttsEngine,
    parseBook: (raw) async {
      // 直接调用内部同步逻辑（非 Isolate）——只能用 parse 公开接口
      return TextParser.parse(raw);
    },
  );

  return (reader, ttsEngine);
}

// ── 测试主体 ──────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── 初始状态 ──────────────────────────────────────────────────────────────────

  group('听书集成 - ReaderProvider 初始状态', () {
    test('初始 sentences 为空', () async {
      final (reader, tts) = await _makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });

      expect(reader.sentences, isEmpty);
    });

    test('初始 currentIndex 为 0', () async {
      final (reader, tts) = await _makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });

      expect(reader.currentIndex, 0);
    });

    test('初始 isParsing 为 false', () async {
      final (reader, tts) = await _makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });

      expect(reader.isParsing, isFalse);
    });
  });

  // ── 书籍加载流程 ──────────────────────────────────────────────────────────────

  group('听书集成 - 书籍加载流程', () {
    test('loadBook 后 sentences 非空', () async {
      final (reader, tts) = await _makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });

      await reader.loadBook('第一句话。第二句话。第三句话。', bookId: 'b1');

      expect(reader.sentences, isNotEmpty);
      expect(reader.currentBookId, 'b1');
    });

    test('loadBook 解析完成后 isParsing 恢复为 false', () async {
      final (reader, tts) = await _makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });

      await reader.loadBook('内容测试句子。', bookId: 'b2');

      expect(reader.isParsing, isFalse);
    });

    test('loadBook 中文标点正确切分句子', () async {
      final (reader, tts) = await _makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });

      await reader.loadBook('第一句。第二句！第三句？', bookId: 'b3');

      expect(reader.sentences.length, 3);
    });

    test('loadPreparedBook 直接加载已切分行', () async {
      final (reader, tts) = await _makeStack();
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
      final (reader, tts) = await _makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });

      await reader.loadBook('', bookId: 'empty_1');

      expect(reader.sentences, isEmpty);
      expect(reader.isParsing, isFalse);
    });
  });

  // ── 进度导航流程 ──────────────────────────────────────────────────────────────

  group('听书集成 - 进度导航流程', () {
    test('nextSentence 推进 currentIndex', () async {
      final (reader, tts) = await _makeStack();
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
      final (reader, tts) = await _makeStack();
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
      final (reader, tts) = await _makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });

      await reader.loadBook('只有一句。', bookId: 'nav_3');
      await reader.previousSentence();

      expect(reader.currentIndex, 0);
    });

    test('jumpTo 边界索引不崩溃', () async {
      final (reader, tts) = await _makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });

      await reader.loadBook('第一句。第二句。', bookId: 'nav_4');

      // 越界负数不崩溃
      await reader.jumpTo(-1);
      // 越界正数不崩溃
      await reader.jumpTo(9999);

      expect(reader.currentIndex, isNonNegative);
    });

    test('jumpTo 合法 index 跳转', () async {
      final (reader, tts) = await _makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });

      await reader.loadBook('第一句。第二句。第三句。', bookId: 'nav_5');
      await reader.jumpTo(2);

      expect(reader.currentIndex, 2);
    });
  });

  // ── 章节切换流程 ──────────────────────────────────────────────────────────────

  group('听书集成 - 章节加载与切换', () {
    test('带章节的书籍正确挂载章节列表', () async {
      final (reader, tts) = await _makeStack();
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
      final (reader, tts) = await _makeStack();
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

  // ── TTS 切换流程 ──────────────────────────────────────────────────────────────

  group('听书集成 - TTS 切换流程', () {
    test('无书籍时 toggleTTS 返回 noContent', () async {
      final (reader, tts) = await _makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });

      final result = reader.toggleTTS();
      expect(result, TtsToggleResult.noContent);
    });

    test('有书籍时 toggleTTS 可正常切换状态', () async {
      final (reader, tts) = await _makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });

      await reader.loadBook('播放测试句子。', bookId: 'tts_1');
      final result = reader.toggleTTS();

      // 切换后不会返回 noContent
      expect(result, isNot(TtsToggleResult.noContent));
    });

    test('书籍删除后 resetForDeletedBook 清空所有数据', () async {
      final (reader, tts) = await _makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });

      await reader.loadBook('测试书籍内容。', bookId: 'del_1');
      expect(reader.sentences, isNotEmpty);

      reader.resetForDeletedBook('del_1');
      expect(reader.sentences, isEmpty);
      expect(reader.currentBookId, isNull);
      expect(reader.currentIndex, 0);
    });

    test('resetForDeletedBook 对不同 bookId 不产生影响', () async {
      final (reader, tts) = await _makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });

      await reader.loadBook('保留的书籍内容。', bookId: 'keep_1');
      reader.resetForDeletedBook('other_book'); // 删除的是其他书

      expect(reader.sentences, isNotEmpty);
      expect(reader.currentBookId, 'keep_1');
    });
  });

  // ── 进度持久化流程 ────────────────────────────────────────────────────────────

  group('听书集成 - 进度持久化', () {
    test('nextSentence 后进度可以通过 StorageService 读取', () async {
      final (reader, tts) = await _makeStack();
      addTearDown(() {
        reader.dispose();
        tts.dispose();
      });

      await reader.loadBook('第一句。第二句。第三句。', bookId: 'progress_1');
      await reader.nextSentence();

      // 给异步存档时间
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final record = StorageService.getReadingRecord('progress_1');
      expect(record['cursor'], 1);
    });
  });
}
