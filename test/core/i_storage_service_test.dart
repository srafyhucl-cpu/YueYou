import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/database/i_storage_service.dart';
import 'package:yueyou/core/database/local_storage_service.dart';
import 'package:yueyou/core/database/storage_service.dart';

/// Mock 实现：完全内存化，不依赖任何平台插件
/// 用于验证接口契约：上层代码只依赖 [IStorageService]，
/// 可在测试中随时替换为本 Mock，无需 SharedPreferences 或文件系统。
class _MockStorageService implements IStorageService {
  // 内存存储
  final Map<String, dynamic> _gameState = {};
  final List<Map<String, dynamic>> _bookshelf = [];
  final Map<String, Map<String, dynamic>> _readingRecords = {};
  String? _currentNovelId;
  int _currentNovelIndex = 0;
  final Map<String, Map<String, dynamic>> _bookContents = {};

  bool _soundEnabled = true;
  bool _storyTtsEnabled = true;
  String _voice = 'zh-CN-XiaoxiaoNeural';
  int _idleTimeout = 1;
  double _ttsRate = 1.0;
  double _ambientVol = 0.5;
  bool _ambientEnabled = true;
  bool _hasAgreedPrivacy = false;
  bool _hasSelectedBook = false;
  final Map<String, Map<int, String>> _chapterCache = {};
  final Map<String, List<Map<String, dynamic>>> _catalogCache = {};

  @override
  Future<void> init() async {}

  // ── 游戏状态 ──────────────────────────────────────────────────────────────

  @override
  Future<void> saveGameState({
    required List<List<Map<String, dynamic>?>> board,
    required int score,
    required int combo,
    required int bestScore,
    required int maxCombo,
    required int novelIndex,
    String? currentNovelId,
  }) async {
    _gameState['board'] = board;
    _gameState['score'] = score;
    _gameState['combo'] = combo;
    _gameState['bestScore'] = bestScore;
    _gameState['maxCombo'] = maxCombo;
    _gameState['novelIndex'] = novelIndex;
    _gameState['currentNovelId'] = currentNovelId;
  }

  @override
  Map<String, dynamic>? loadGameState() =>
      _gameState.isEmpty ? null : Map.from(_gameState);

  @override
  int loadBestScore() => (_gameState['bestScore'] as int?) ?? 0;

  @override
  int loadMaxCombo() => (_gameState['maxCombo'] as int?) ?? 0;

  // ── 书架元数据 ────────────────────────────────────────────────────────────

  @override
  Future<void> saveBookshelf(List<Map<String, dynamic>> shelf) async {
    _bookshelf
      ..clear()
      ..addAll(shelf);
  }

  @override
  List<Map<String, dynamic>> loadBookshelf() => List.from(_bookshelf);

  // ── 阅读进度 ──────────────────────────────────────────────────────────────

  @override
  Future<void> updateReadingRecord(String bookId, int cursor, int total) async {
    if (total <= 0) return;
    _readingRecords[bookId] = {
      'cursor': cursor,
      'total': total,
      'percent': (cursor / total * 100).clamp(0.0, 100.0),
    };
  }

  @override
  Map<String, dynamic> getReadingRecord(String bookId) =>
      _readingRecords[bookId] ?? {'cursor': 0, 'total': 1, 'percent': 0.0};

  @override
  Future<void> deleteReadingRecord(String bookId) async =>
      _readingRecords.remove(bookId);

  // ── 当前小说状态 ──────────────────────────────────────────────────────────

  @override
  Future<void> setCurrentNovelId(String? id) async => _currentNovelId = id;

  @override
  String? getCurrentNovelId() => _currentNovelId;

  @override
  int getCurrentNovelIndex() => _currentNovelIndex;

  @override
  Future<void> setCurrentNovelIndex(int index) async =>
      _currentNovelIndex = index;

  // ── 书籍正文内容 ──────────────────────────────────────────────────────────

  @override
  Future<void> saveBookContent(
    String bookId, {
    required List<String> lines,
    required List<Map<String, dynamic>> chapters,
  }) async {
    _bookContents[bookId] = {'lines': lines, 'chapters': chapters};
  }

  @override
  Future<Map<String, dynamic>?> loadBookContent(String bookId) async =>
      _bookContents[bookId];

  @override
  Future<void> deleteBookContent(String bookId) async =>
      _bookContents.remove(bookId);

  // ── 全局设置 ──────────────────────────────────────────────────────────────

  @override
  bool getSettingSound() => _soundEnabled;
  @override
  Future<void> setSettingSound(bool v) async => _soundEnabled = v;

  @override
  bool getSettingStoryTts() => _storyTtsEnabled;
  @override
  Future<void> setSettingStoryTts(bool v) async => _storyTtsEnabled = v;

  @override
  String getSettingVoice() => _voice;
  @override
  Future<void> setSettingVoice(String v) async => _voice = v;

  @override
  int getSettingIdleTimeout() => _idleTimeout;
  @override
  Future<void> setSettingIdleTimeout(int v) async => _idleTimeout = v;

  @override
  double getSettingTtsRate() => _ttsRate;
  @override
  Future<void> setSettingTtsRate(double v) async => _ttsRate = v;

  @override
  double getSettingAmbientVol() => _ambientVol;
  @override
  Future<void> setSettingAmbientVol(double v) async => _ambientVol = v;

  @override
  bool getSettingAmbientEnabled() => _ambientEnabled;
  @override
  Future<void> setSettingAmbientEnabled(bool v) async => _ambientEnabled = v;

  // ── 隐私协议 ──────────────────────────────────────────────────────────────

  @override
  bool hasAgreedPrivacy() => _hasAgreedPrivacy;
  @override
  Future<void> setHasAgreedPrivacy(bool v) async => _hasAgreedPrivacy = v;

  // ── 粘性位 ──────────────────────────────────────────────────────

  @override
  bool hasSelectedBook() => _hasSelectedBook;
  @override
  Future<void> setHasSelectedBook(bool v) async => _hasSelectedBook = v;

  // ── 分章文本缓存 ──────────────────────────────────────────────────

  @override
  Future<void> saveChapterCache(
    String bookId,
    int chapterIndex,
    String text,
  ) async {
    _chapterCache.putIfAbsent(bookId, () => {})[chapterIndex] = text;
  }

  @override
  Future<String?> loadChapterCache(String bookId, int chapterIndex) async =>
      _chapterCache[bookId]?[chapterIndex];

  @override
  Future<void> clearChapterCache(String bookId) async =>
      _chapterCache.remove(bookId);

  @override
  Future<void> pruneChapterCache(
    String bookId,
    int currentChapterIndex, {
    int keepAround = 3,
  }) async {
    final cache = _chapterCache[bookId];
    if (cache == null) return;
    final keepMin = currentChapterIndex - keepAround;
    final keepMax = currentChapterIndex + keepAround;
    cache.removeWhere((idx, _) => idx < keepMin || idx > keepMax);
  }

  // ── 目录缓存 ────────────────────────────────────────────────────

  @override
  Future<void> saveBookCatalog(
    String bookId,
    List<Map<String, dynamic>> chapters,
  ) async {
    _catalogCache[bookId] = List.from(chapters);
  }

  @override
  Future<List<Map<String, dynamic>>?> loadBookCatalog(String bookId) async =>
      _catalogCache[bookId];
}

/// 辅助：路径 Provider mock
void _mockPathProvider(String documentsDir) {
  const MethodChannel channel =
      MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    channel,
    (MethodCall call) async => documentsDir,
  );
}

/// 在 [IStorageService] 上执行的通用契约测试
///
/// 同一组测试可针对 [_MockStorageService] 和 [LocalStorageService] 运行，
/// 验证两者行为完全一致，确保接口契约正确性。
/// [skipBookContent]：为 true 时跳过书籍正文测试（需 path_provider mock 的实现使用）
void _runContractTests(
  IStorageService Function() factory, {
  bool skipBookContent = false,
}) {
  late IStorageService storage;

  setUp(() async {
    storage = factory();
    await storage.init();
  });

  // ── 游戏状态契约 ──────────────────────────────────────────────────────────

  group('游戏状态契约', () {
    test('初始无存档时 loadGameState 返回 null', () {
      expect(storage.loadGameState(), isNull);
    });

    test('初始 bestScore 为 0', () {
      expect(storage.loadBestScore(), 0);
    });

    test('初始 maxCombo 为 0', () {
      expect(storage.loadMaxCombo(), 0);
    });

    test('saveGameState 后 loadGameState 返回正确数据', () async {
      await storage.saveGameState(
        board: List.generate(4, (_) => List.filled(4, null)),
        score: 256,
        combo: 3,
        bestScore: 512,
        maxCombo: 7,
        novelIndex: 2,
        currentNovelId: 'novel_abc',
      );
      expect(storage.loadBestScore(), 512);
      expect(storage.loadMaxCombo(), 7);
      final state = storage.loadGameState();
      expect(state, isNotNull);
    });
  });

  // ── 书架元数据契约 ────────────────────────────────────────────────────────

  group('书架元数据契约', () {
    test('初始书架为空', () {
      expect(storage.loadBookshelf(), isEmpty);
    });

    test('saveBookshelf 后 loadBookshelf 往返一致', () async {
      final shelf = [
        <String, dynamic>{'id': '1', 'title': '测试书 A', 'total': 500},
        <String, dynamic>{'id': '2', 'title': '测试书 B', 'total': 200},
      ];
      await storage.saveBookshelf(shelf);
      final loaded = storage.loadBookshelf();
      expect(loaded.length, 2);
      expect(loaded.first['title'], '测试书 A');
    });

    test('覆盖写入后只保留最新数据', () async {
      await storage.saveBookshelf([
        <String, dynamic>{'id': '1', 'title': '旧书', 'total': 100},
      ]);
      await storage.saveBookshelf([]);
      expect(storage.loadBookshelf(), isEmpty);
    });
  });

  // ── 阅读进度契约 ──────────────────────────────────────────────────────────

  group('阅读进度契约', () {
    test('无记录时返回零进度', () {
      final record = storage.getReadingRecord('unknown_book');
      expect(record['cursor'], 0);
      expect(record['percent'], 0.0);
    });

    test('updateReadingRecord 后 getReadingRecord 返回正确进度', () async {
      await storage.updateReadingRecord('book_1', 50, 100);
      final record = storage.getReadingRecord('book_1');
      expect(record['cursor'], 50);
      expect(record['total'], 100);
      expect(record['percent'], closeTo(50.0, 0.01));
    });

    test('total <= 0 时不写入记录', () async {
      await storage.updateReadingRecord('book_zero', 0, 0);
      expect(storage.getReadingRecord('book_zero')['cursor'], 0);
    });

    test('deleteReadingRecord 后恢复默认值', () async {
      await storage.updateReadingRecord('book_del', 30, 60);
      await storage.deleteReadingRecord('book_del');
      expect(storage.getReadingRecord('book_del')['cursor'], 0);
    });
  });

  // ── 当前小说状态契约 ──────────────────────────────────────────────────────

  group('当前小说状态契约', () {
    test('初始小说 ID 为 null', () {
      expect(storage.getCurrentNovelId(), isNull);
    });

    test('setCurrentNovelId 后可读取', () async {
      await storage.setCurrentNovelId('novel_123');
      expect(storage.getCurrentNovelId(), 'novel_123');
    });

    test('setCurrentNovelId(null) 清除 ID', () async {
      await storage.setCurrentNovelId('novel_123');
      await storage.setCurrentNovelId(null);
      expect(storage.getCurrentNovelId(), isNull);
    });

    test('初始小说索引为 0', () {
      expect(storage.getCurrentNovelIndex(), 0);
    });

    test('setCurrentNovelIndex 后可读取', () async {
      await storage.setCurrentNovelIndex(5);
      expect(storage.getCurrentNovelIndex(), 5);
    });
  });

  // ── 书籍正文内容契约（skipBookContent=true 时跳过，LocalStorageService 专属 group 单独覆盖）─────────

  group('书籍正文内容契约',
      skip: skipBookContent ? '需 path_provider mock，见专属 group' : null, () {
    test('不存在的书籍 loadBookContent 返回 null', () async {
      expect(await storage.loadBookContent('not_found'), isNull);
    });

    test('saveBookContent 后 loadBookContent 往返一致', () async {
      await storage.saveBookContent(
        'book_a',
        lines: ['第一行', '第二行'],
        chapters: [
          {'title': '第一章', 'lineIndex': 0},
        ],
      );
      final loaded = await storage.loadBookContent('book_a');
      expect(loaded, isNotNull);
      expect((loaded!['lines'] as List).cast<String>(), ['第一行', '第二行']);
    });

    test('deleteBookContent 后 loadBookContent 返回 null', () async {
      await storage.saveBookContent(
        'book_b',
        lines: ['line'],
        chapters: [],
      );
      await storage.deleteBookContent('book_b');
      expect(await storage.loadBookContent('book_b'), isNull);
    });

    test('deleteBookContent 对不存在文件不抛异常', () async {
      expect(
        () async => storage.deleteBookContent('not_exist'),
        returnsNormally,
      );
    });
  });

  // ── 全局设置契约 ──────────────────────────────────────────────────────────

  group('全局设置契约', () {
    test('音效默认 true，可关闭', () async {
      expect(storage.getSettingSound(), isTrue);
      await storage.setSettingSound(false);
      expect(storage.getSettingSound(), isFalse);
    });

    test('TTS 默认 true，可关闭', () async {
      expect(storage.getSettingStoryTts(), isTrue);
      await storage.setSettingStoryTts(false);
      expect(storage.getSettingStoryTts(), isFalse);
    });

    test('TTS 音色可设置并读取', () async {
      await storage.setSettingVoice('zh-CN-YunxiNeural');
      expect(storage.getSettingVoice(), 'zh-CN-YunxiNeural');
    });

    test('空闲超时可设置并读取', () async {
      await storage.setSettingIdleTimeout(30);
      expect(storage.getSettingIdleTimeout(), 30);
    });

    test('TTS 倍速可设置并读取', () async {
      await storage.setSettingTtsRate(1.5);
      expect(storage.getSettingTtsRate(), closeTo(1.5, 0.001));
    });

    test('环境音量可设置并读取', () async {
      await storage.setSettingAmbientVol(0.8);
      expect(storage.getSettingAmbientVol(), closeTo(0.8, 0.001));
    });

    test('环境音乐开关可设置并读取', () async {
      await storage.setSettingAmbientEnabled(false);
      expect(storage.getSettingAmbientEnabled(), isFalse);
    });
  });

  // ── 隐私协议契约 ──────────────────────────────────────────────────────────

  group('隐私协议契约', () {
    test('默认未同意', () {
      expect(storage.hasAgreedPrivacy(), isFalse);
    });

    test('setHasAgreedPrivacy(true) 后 hasAgreedPrivacy 返回 true', () async {
      await storage.setHasAgreedPrivacy(true);
      expect(storage.hasAgreedPrivacy(), isTrue);
    });
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── MockStorageService 接口契约测试 ────────────────────────────────────────

  group('IStorageService 契约 - MockStorageService（纯内存，无平台依赖）', () {
    _runContractTests(() => _MockStorageService());
  });

  // ── LocalStorageService 接口契约测试 ──────────────────────────────────────

  group('IStorageService 契约 - LocalStorageService（委托 StorageService）', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      StorageService.resetForTesting();
    });

    _runContractTests(() => LocalStorageService(), skipBookContent: true);
  });

  // ── LocalStorageService 书籍正文需要路径 mock 单独测试 ──────────────────────

  group('LocalStorageService - 书籍正文（需路径 mock）', () {
    late LocalStorageService storage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      StorageService.resetForTesting();
      storage = LocalStorageService();
      await storage.init();
    });

    test('saveBookContent / loadBookContent 往返一致', () async {
      final dir = await Directory.systemTemp.createTemp('yueyou_iface_');
      _mockPathProvider(dir.path);

      await storage.saveBookContent(
        'book_iface',
        lines: ['行一', '行二'],
        chapters: [
          {'title': '第一章', 'lineIndex': 0},
        ],
      );
      final loaded = await storage.loadBookContent('book_iface');
      expect(loaded, isNotNull);
      expect((loaded!['lines'] as List).cast<String>(), ['行一', '行二']);
    });

    test('deleteBookContent 后 loadBookContent 返回 null', () async {
      final dir = await Directory.systemTemp.createTemp('yueyou_iface_');
      _mockPathProvider(dir.path);

      await storage.saveBookContent(
        'book_del_iface',
        lines: ['L1'],
        chapters: [],
      );
      await storage.deleteBookContent('book_del_iface');
      expect(await storage.loadBookContent('book_del_iface'), isNull);
    });
  });
}
