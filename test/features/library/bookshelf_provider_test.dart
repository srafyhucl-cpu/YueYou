import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/features/library/domain/book_model.dart';
import 'package:yueyou/features/library/providers/bookshelf_provider.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';

void _mockAppChannels() {
  const MethodChannel pathProvider =
      MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProvider, (MethodCall call) async {
    return '.';
  });

  const MethodChannel audioGlobal =
      MethodChannel('xyz.luan/audioplayers.global');
  const MethodChannel audioPlayer = MethodChannel('xyz.luan/audioplayers');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(audioGlobal, (MethodCall call) async {
    return null;
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(audioPlayer, (MethodCall call) async {
    return null;
  });
}

Future<void> _initStorage() async {
  SharedPreferences.setMockInitialValues({});
  StorageService.resetForTesting();
  await StorageService.init();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BookshelfProvider', () {
    setUp(() async {
      await _initStorage();
      _mockAppChannels();
    });

    test('addBook 后 shelf 包含新书且排在首位', () async {
      final provider = BookshelfProvider();
      await provider.addBook(
        id: 1,
        title: '测试小说',
        lines: ['第一章 开始', '内容一'],
        chapters: [const ChapterModel(title: '第一章 开始', lineIndex: 0)],
      );

      expect(provider.shelf.length, 1);
      expect(provider.shelf.first.title, '测试小说');
      expect(provider.shelf.first.id, 1);
    });

    test('addBook 同名书替换旧书', () async {
      final provider = BookshelfProvider();
      await provider.addBook(
        id: 1,
        title: '重复书',
        lines: ['旧内容'],
        chapters: [],
      );
      await provider.addBook(
        id: 2,
        title: '重复书',
        lines: ['新内容'],
        chapters: [],
      );

      expect(provider.shelf.length, 1);
      expect(provider.shelf.first.id, 2);
    });

    test('deleteBook 从 shelf 移除并通知', () async {
      final provider = BookshelfProvider();
      await provider.addBook(
        id: 42,
        title: '待删除',
        lines: ['内容'],
        chapters: [],
      );
      expect(provider.shelf.length, 1);

      int notified = 0;
      provider.addListener(() => notified++);

      await provider.deleteBook(42);

      expect(provider.shelf, isEmpty);
      expect(notified, greaterThan(0));
    });

    test('deleteBook 级联重置当前阅读中的 ReaderProvider', () async {
      final settings = SettingsProvider();
      settings.loadFromStorage();
      settings.storyTts = false;
      final tts = TtsEngineService(settings);
      final reader = ReaderProvider(tts);

      await reader.loadBook('第一章\n内容一\n内容二\n',
          bookId: '99', initialIndex: 0, forceIndex: true);
      expect(reader.currentBookId, '99');

      final provider = BookshelfProvider();
      await provider.addBook(
        id: 99,
        title: '级联书',
        lines: ['第一章', '内容一', '内容二'],
        chapters: [],
      );

      await provider.deleteBook(99, reader: reader);

      expect(provider.shelf, isEmpty);
      expect(reader.currentBookId, isNull);
      expect(reader.sentences, isEmpty);
    });

    test('deleteBook 不存在的 id 不影响 shelf', () async {
      final provider = BookshelfProvider();
      await provider.addBook(
        id: 1,
        title: '保留书',
        lines: ['内容'],
        chapters: [],
      );

      await provider.deleteBook(999);

      expect(provider.shelf.length, 1);
      expect(provider.shelf.first.id, 1);
    });

    test('getReadingPercent 和 getReadingCursor 返回默认值', () {
      final provider = BookshelfProvider();
      expect(provider.getReadingPercent(1), 0.0);
      expect(provider.getReadingCursor(1), 0);
    });
  });
}
