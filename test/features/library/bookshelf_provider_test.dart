import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/constants/book_constants.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/features/library/domain/book_model.dart';
import 'package:yueyou/features/library/providers/bookshelf_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';

void _mockAppChannels(String documentsPath) {
  const MethodChannel pathProvider =
      MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProvider, (MethodCall call) async {
    return documentsPath;
  });

  const MethodChannel audioGlobal =
      MethodChannel('xyz.luan/audioplayers.global');
  const MethodChannel audioPlayer = MethodChannel('xyz.luan/audioplayers');
  const MethodChannel flutterTts = MethodChannel('flutter_tts');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(audioGlobal, (MethodCall call) async {
    return null;
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(audioPlayer, (MethodCall call) async {
    return null;
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(flutterTts, (MethodCall call) async {
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
    Directory? tempDir;

    setUp(() async {
      final tempRoot = Directory(r'D:\Temp');
      await tempRoot.create(recursive: true);
      tempDir = await tempRoot.createTemp('yueyou_bookshelf_');
      _mockAppChannels(tempDir!.path);
      await _initStorage();
      // 单测不需要自动注入写游记副作用，设置粘性位抑制 injectDefaultBookIfNeeded
      await StorageService.setHasSelectedBook(true);
    });

    tearDown(() async {
      final directory = tempDir;
      tempDir = null;
      if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    test('addBook 后 shelf 包含新书且排在首位', () async {
      final container = ProviderContainer();
      final provider = container.read(bookshelfProvider.notifier);
      final loadingSnapshots = <bool>[];
      provider.addListener(() => loadingSnapshots.add(provider.isLoading));

      await provider.addBook(
        id: 1,
        title: '测试小说',
        lines: ['第一章 开始', '内容一'],
        chapters: [const ChapterModel(title: '第一章 开始', lineIndex: 0)],
      );

      expect(provider.shelf.length, 1);
      expect(provider.shelf.first.title, '测试小说');
      expect(provider.shelf.first.id, 1);
      expect(loadingSnapshots, containsAllInOrder([true, false]));
    });

    test('addBook 同名书替换旧书', () async {
      final container = ProviderContainer();
      final provider = container.read(bookshelfProvider.notifier);
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
      final container = ProviderContainer();
      final provider = container.read(bookshelfProvider.notifier);
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

      await reader.loadBook(
        '第一章\n内容一\n内容二\n',
        bookId: '99',
        initialIndex: 0,
        forceIndex: true,
      );
      expect(reader.currentBookId, '99');

      final container = ProviderContainer();
      final provider = container.read(bookshelfProvider.notifier);
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
      final container = ProviderContainer();
      final provider = container.read(bookshelfProvider.notifier);
      await provider.addBook(
        id: 1,
        title: '保留书',
        lines: ['内容'],
        chapters: [],
      );

      // 9999 是真正不存在的 id，999 是默认书 id 已有具体语义
      await provider.deleteBook(9999);

      expect(provider.shelf.length, 1);
      expect(provider.shelf.first.id, 1);
    });

    test('getReadingPercent 和 getReadingCursor 返回默认值', () {
      final container = ProviderContainer();
      final provider = container.read(bookshelfProvider.notifier);
      expect(provider.getReadingPercent(1), 0.0);
      expect(provider.getReadingCursor(1), 0);
    });

    test('deleteBook 删除默认书时写入粘性位，防止下次启动再次自动注入', () async {
      // 先清除粘性位，模拟首次启动状态
      await StorageService.setHasSelectedBook(false);

      final container = ProviderContainer();
      final provider = container.read(bookshelfProvider.notifier);

      // 向书架添加默认书（使用 defaultBookId）
      await provider.addBook(
        id: BookConstants.defaultBookId,
        title: '西游记',
        lines: ['第一回'],
        chapters: [const ChapterModel(title: '第一回', lineIndex: 0)],
      );

      // 删除默认书
      await provider.deleteBook(BookConstants.defaultBookId);

      // 粘性位必须已写入（E2 修复验证：await 保证写盘完成）
      expect(StorageService.hasSelectedBook(), isTrue);
      expect(provider.shelf, isEmpty);
    });

    test('deleteBook 删除非默认书不写粘性位', () async {
      await StorageService.setHasSelectedBook(false);

      final container = ProviderContainer();
      final provider = container.read(bookshelfProvider.notifier);
      await provider.addBook(
        id: 7,
        title: '三国演义',
        lines: ['第一回'],
        chapters: [],
      );
      await provider.deleteBook(7);

      // 删除普通书不应改变粘性位
      expect(StorageService.hasSelectedBook(), isFalse);
    });

    test('loadBookContent 返回 addBook 写入的正文内容', () async {
      final container = ProviderContainer();
      final provider = container.read(bookshelfProvider.notifier);
      await provider.addBook(
        id: 31,
        title: '正文读取书',
        lines: ['第一行', '第二行'],
        chapters: [const ChapterModel(title: '第一章', lineIndex: 0)],
      );

      final content = await provider.loadBookContent(31);

      expect(content, isNotNull);
      expect((content!['lines'] as List).cast<String>(), ['第一行', '第二行']);
    });

    test('setShelfForTesting 仅替换内存书架并通知监听者', () {
      final provider = BookshelfProvider();
      var notified = 0;
      provider.addListener(() => notified++);

      provider.setShelfForTesting([
        const BookModel(id: 9, title: '测试注入', total: 1),
      ]);

      expect(provider.shelf.single.title, '测试注入');
      expect(notified, 1);
    });

    test('addDefaultBook 已存在默认书时不重复写入', () async {
      final provider = BookshelfProvider();
      await provider.addDefaultBook([
        const ChapterModel(title: '第一回', lineIndex: 0),
      ]);

      await provider.addDefaultBook([
        const ChapterModel(title: '第二回', lineIndex: 1),
      ]);

      expect(provider.shelf.length, 1);
      expect(provider.shelf.single.id, BookConstants.defaultBookId);
    });

    test('injectDefaultBookIfNeeded 遇到粘性位时直接跳过', () async {
      await StorageService.setHasSelectedBook(true);
      final provider = BookshelfProvider();

      await provider.injectDefaultBookIfNeeded();

      expect(provider.shelf, isEmpty);
    });
  });
}
