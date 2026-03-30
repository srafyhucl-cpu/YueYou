import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/features/library/domain/book_model.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';

void _mockAudioplayersChannels() {
  const MethodChannel global = MethodChannel('xyz.luan/audioplayers.global');
  const MethodChannel player = MethodChannel('xyz.luan/audioplayers');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(global, (MethodCall call) async {
    // 返回空即可绕过 initialize 等调用
    return null;
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(player, (MethodCall call) async {
    // 拦截所有 AudioPlayer 方法调用，返回空
    return null;
  });
}

Future<ReaderProvider> _makeReaderProvider({bool ttsEnabled = false}) async {
  SharedPreferences.setMockInitialValues({});
  StorageService.resetForTesting();
  await StorageService.init();

  // Mock 掉 audioplayers 的 MethodChannel，避免 MissingPluginException
  _mockAudioplayersChannels();

  final settings = SettingsProvider();
  settings.loadFromStorage();
  if (!ttsEnabled) {
    settings.storyTts = false; // 保证 ReaderProvider.loadBook 不触发 refreshSession
  }

  final tts = TtsEngineService(settings);
  return ReaderProvider(tts);
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
  });

  group('ReaderProvider - 预取与步进', () {
    test('onNeedPrefetch 合并短句至≥5字符，并推进 fetchIndex', () async {
      final reader = await _makeReaderProvider();
      const raw = '标题\n短\n词\n段。\n结尾。\n';
      await reader.loadBook(raw,
          bookId: 'b2', initialIndex: 0, forceIndex: true);

      // 跳到“短”所在句，验证合并行为
      final shortIdx = reader.sentences.indexOf('短');
      expect(shortIdx, isNonNegative);
      await reader.jumpTo(shortIdx);
      final before = reader.fetchIndex;

      final req = await reader.ttsEngine.onNeedPrefetch?.call(0);
      expect(req, isNotNull);
      expect(req!.text.length, greaterThanOrEqualTo(5));
      expect(req.text.startsWith('短'), isTrue);
      // 当 consumed 正好到达末尾时，内部会将 fetchIndex 取模为 0
      expect(reader.fetchIndex, anyOf(greaterThan(before), equals(0)));
    });

    test('nextSentence 步进：currentIndex 与 fetchIndex 同步递增', () async {
      final reader = await _makeReaderProvider();
      const raw = 'A。\nB。\nC。\n';
      await reader.loadBook(raw,
          bookId: 'b3', initialIndex: 0, forceIndex: true);
      final prev = reader.currentIndex;
      await reader.nextSentence();
      expect(reader.currentIndex, prev + 1);
      expect(reader.fetchIndex, reader.currentIndex);
    });

    test('jumpTo 跳过噪音行并同步 fetchIndex', () async {
      final reader = await _makeReaderProvider();
      const raw = '***\n有效句。\n';
      await reader.loadBook(raw,
          bookId: 'b4', initialIndex: 0, forceIndex: true);
      // 跳到第0行（噪音），应自动跳到下一有效句
      await reader.jumpTo(0);
      expect(reader.currentSentence, '有效句。');
      expect(reader.fetchIndex, reader.currentIndex);
    });
  });
}
