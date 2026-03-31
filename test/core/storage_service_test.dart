import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/database/storage_service.dart';

void _mockPathProvider(String documentsDir) {
  const MethodChannel channel =
      MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    if (call.method == 'getApplicationDocumentsDirectory') {
      return documentsDir;
    }
    if (call.method == 'getTemporaryDirectory') {
      return documentsDir;
    }
    if (call.method == 'getApplicationSupportDirectory') {
      return documentsDir;
    }
    return documentsDir;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTesting();
    await StorageService.init();
  });

  // ── 游戏状态 ────────────────────────────────────────────────────────────────

  group('StorageService - 游戏状态', () {
    test('初始最佳分数为 0', () {
      expect(StorageService.loadBestScore(), 0);
    });

    test('初始最大连击为 0', () {
      expect(StorageService.loadMaxCombo(), 0);
    });

    test('无存档时 loadGameState 返回 null', () {
      expect(StorageService.loadGameState(), isNull);
    });

    test('存档 JSON 损坏时 loadGameState 返回 null', () async {
      SharedPreferences.setMockInitialValues({'local_save_data': '{'});
      StorageService.resetForTesting();
      await StorageService.init();
      expect(StorageService.loadGameState(), isNull);
    });

    test('保存后 loadGameState 恢复完整快照', () async {
      final board = List.generate(
        4,
        (r) => List.generate(
          4,
          (c) =>
              r == 0 && c == 0 ? <String, dynamic>{'id': 1, 'value': 2} : null,
        ),
      );

      await StorageService.saveGameState(
        board: board,
        score: 42,
        combo: 3,
        bestScore: 100,
        maxCombo: 5,
        novelIndex: 7,
        currentNovelId: 'novel_1',
      );

      final loaded = StorageService.loadGameState();
      expect(loaded, isNotNull);
      expect(loaded!['score'], 42);
      expect(loaded['combo'], 3);
      expect(loaded['bestScore'], 100);
      expect(loaded['maxCombo'], 5);
    });

    test('saveGameState 同步写入 bestScore 快捷键', () async {
      await StorageService.saveGameState(
        board: List.generate(4, (_) => List.filled(4, null)),
        score: 0,
        combo: 0,
        bestScore: 888,
        maxCombo: 0,
        novelIndex: 0,
      );

      expect(StorageService.loadBestScore(), 888);
    });

    test('saveGameState 同步写入 maxCombo 快捷键', () async {
      await StorageService.saveGameState(
        board: List.generate(4, (_) => List.filled(4, null)),
        score: 0,
        combo: 0,
        bestScore: 0,
        maxCombo: 12,
        novelIndex: 0,
      );

      expect(StorageService.loadMaxCombo(), 12);
    });
  });

  // ── 阅读进度 ─────────────────────────────────────────────────────────────────

  group('StorageService - 阅读进度', () {
    test('未记录的书籍返回默认进度', () {
      final record = StorageService.getReadingRecord('book_999');
      expect(record['cursor'], 0);
      expect(record['percent'], 0.0);
    });

    test('updateReadingRecord 后可读取正确进度', () async {
      await StorageService.updateReadingRecord('book_1', 50, 100);

      final record = StorageService.getReadingRecord('book_1');
      expect(record['cursor'], 50);
      expect(record['total'], 100);
      expect(record['percent'], closeTo(50.0, 0.01));
    });

    test('deleteReadingRecord 后恢复默认值', () async {
      await StorageService.updateReadingRecord('book_2', 30, 60);
      await StorageService.deleteReadingRecord('book_2');

      final record = StorageService.getReadingRecord('book_2');
      expect(record['cursor'], 0);
    });

    test('total 为 0 时不写入记录（防止除零）', () async {
      await StorageService.updateReadingRecord('book_zero', 0, 0);
      // 防御：total<=0 时方法提前返回，不写入
      final record = StorageService.getReadingRecord('book_zero');
      expect(record['cursor'], 0);
    });

    test('reading_records JSON 损坏时返回空 Map', () async {
      SharedPreferences.setMockInitialValues({'reading_records': '{'});
      StorageService.resetForTesting();
      await StorageService.init();
      expect(StorageService.getReadingRecord('book_x')['cursor'], 0);
    });

    test('percent 保留两位小数', () async {
      await StorageService.updateReadingRecord('book_pct', 1, 3);
      final record = StorageService.getReadingRecord('book_pct');
      expect(record['percent'], closeTo(33.33, 0.01));
    });
  });

  // ── 当前小说 ─────────────────────────────────────────────────────────────────

  group('StorageService - 当前小说', () {
    test('初始当前小说索引为 0', () {
      expect(StorageService.getCurrentNovelIndex(), 0);
    });

    test('setCurrentNovelIndex 后可读取', () async {
      await StorageService.setCurrentNovelIndex(42);
      expect(StorageService.getCurrentNovelIndex(), 42);
    });

    test('初始当前小说 ID 为 null', () {
      expect(StorageService.getCurrentNovelId(), isNull);
    });

    test('setCurrentNovelId 后可读取', () async {
      await StorageService.setCurrentNovelId('novel_123');
      expect(StorageService.getCurrentNovelId(), 'novel_123');
    });

    test('setCurrentNovelId(null) 清除 ID', () async {
      await StorageService.setCurrentNovelId('novel_123');
      await StorageService.setCurrentNovelId(null);
      expect(StorageService.getCurrentNovelId(), isNull);
    });
  });

  // ── 书架元数据 ───────────────────────────────────────────────────────────────

  group('StorageService - 书架', () {
    test('空书架返回空列表', () {
      expect(StorageService.loadBookshelf(), isEmpty);
    });

    test('书架 JSON 损坏时返回空列表', () async {
      SharedPreferences.setMockInitialValues({'local_bookshelf': '{'});
      StorageService.resetForTesting();
      await StorageService.init();
      expect(StorageService.loadBookshelf(), isEmpty);
    });

    test('saveBookshelf / loadBookshelf 往返一致', () async {
      final shelf = [
        <String, dynamic>{'id': 1, 'title': '测试书 A', 'total': 1000},
        <String, dynamic>{'id': 2, 'title': '测试书 B', 'total': 500},
      ];

      await StorageService.saveBookshelf(shelf);

      final loaded = StorageService.loadBookshelf();
      expect(loaded.length, 2);
      expect(loaded.first['title'], '测试书 A');
      expect(loaded.last['total'], 500);
    });

    test('覆盖写入后只保留最新数据', () async {
      await StorageService.saveBookshelf([
        <String, dynamic>{'id': 1, 'title': '旧书', 'total': 100},
      ]);
      await StorageService.saveBookshelf([]);

      expect(StorageService.loadBookshelf(), isEmpty);
    });
  });

  // ── 全局设置 ─────────────────────────────────────────────────────────────────

  group('StorageService - 全局设置', () {
    test('音效默认开启', () {
      expect(StorageService.getSettingSound(), isTrue);
    });

    test('TTS 默认开启', () {
      expect(StorageService.getSettingStoryTts(), isTrue);
    });

    test('TTS 倍速默认为 1.0', () {
      expect(StorageService.getSettingTtsRate(), 1.0);
    });

    test('空闲超时默认为 1 分钟', () {
      expect(StorageService.getSettingIdleTimeout(), 1);
    });

    test('setSettingSound 持久化并可读取', () async {
      await StorageService.setSettingSound(false);
      expect(StorageService.getSettingSound(), isFalse);
    });

    test('setSettingTtsRate 持久化并可读取', () async {
      await StorageService.setSettingTtsRate(1.5);
      expect(StorageService.getSettingTtsRate(), 1.5);
    });

    test('setSettingIdleTimeout 持久化并可读取', () async {
      await StorageService.setSettingIdleTimeout(30);
      expect(StorageService.getSettingIdleTimeout(), 30);
    });

    test('setSettingVoice 持久化并可读取', () async {
      await StorageService.setSettingVoice('zh-CN-YunxiNeural');
      expect(StorageService.getSettingVoice(), 'zh-CN-YunxiNeural');
    });

    test('setSettingAmbientVol 持久化并可读取', () async {
      await StorageService.setSettingAmbientVol(0.8);
      expect(StorageService.getSettingAmbientVol(), closeTo(0.8, 0.001));
    });
  });

  group('StorageService - 书籍正文', () {
    test('saveBookContent / loadBookContent 往返一致', () async {
      final dir = await Directory.systemTemp.createTemp('yueyou_books_');
      _mockPathProvider(dir.path);

      await StorageService.saveBookContent(
        'book_1',
        lines: const ['L1', 'L2'],
        chapters: const [
          {'title': '第一章', 'lineIndex': 0},
        ],
      );

      final loaded = await StorageService.loadBookContent('book_1');
      expect(loaded, isNotNull);
      expect((loaded!['lines'] as List).cast<String>(), ['L1', 'L2']);
      expect((loaded['chapters'] as List).length, 1);
    });

    test('loadBookContent 在文件不存在时返回 null', () async {
      final dir = await Directory.systemTemp.createTemp('yueyou_books_');
      _mockPathProvider(dir.path);
      final loaded = await StorageService.loadBookContent('not_exists');
      expect(loaded, isNull);
    });

    test('deleteBookContent 在文件不存在时不抛异常', () async {
      final dir = await Directory.systemTemp.createTemp('yueyou_books_');
      _mockPathProvider(dir.path);
      expect(() async => StorageService.deleteBookContent('not_exists'),
          returnsNormally);
    });

    test('deleteBookContent 在文件存在时会删除，随后 loadBookContent 返回 null', () async {
      final dir = await Directory.systemTemp.createTemp('yueyou_books_');
      _mockPathProvider(dir.path);

      await StorageService.saveBookContent(
        'book_del',
        lines: const ['L1'],
        chapters: const [],
      );

      expect(await StorageService.loadBookContent('book_del'), isNotNull);

      await StorageService.deleteBookContent('book_del');
      expect(await StorageService.loadBookContent('book_del'), isNull);
    });

    test('loadBookContent 在 JSON 损坏时返回 null', () async {
      final dir = await Directory.systemTemp.createTemp('yueyou_books_');
      _mockPathProvider(dir.path);

      final file = File('${dir.path}/books/book_bad.json');
      await file.parent.create(recursive: true);
      await file.writeAsString('{');

      final loaded = await StorageService.loadBookContent('book_bad');
      expect(loaded, isNull);
    });

    test('saveBookContent 在 IO 异常时不抛出', () async {
      final dir = await Directory.systemTemp.createTemp('yueyou_books_');
      final fakeDocumentsFile = File('${dir.path}/not_a_dir');
      await fakeDocumentsFile.writeAsString('x');

      _mockPathProvider(fakeDocumentsFile.path);
      expect(
        () async => StorageService.saveBookContent(
          'book_io_error',
          lines: const ['L1'],
          chapters: const [],
        ),
        returnsNormally,
      );
    });
  });
}
