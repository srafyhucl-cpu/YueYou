import 'package:yueyou/core/database/i_storage_service.dart';
import 'package:yueyou/core/database/storage_service.dart';

/// [IStorageService] 的本地持久化实现（生产环境注入版本）
///
/// 内部将所有调用委托给 [StorageService] 静态方法，保持与现有
/// SharedPreferences + path_provider 存储行为 100% 一致。
///
/// ## 用法
/// ```dart
/// // 在 main.dart 中完成初始化
/// final storage = LocalStorageService();
/// await storage.init();
/// runApp(MultiProvider(providers: [
///   Provider<IStorageService>.value(value: storage),
///   // ... 其他 Provider
/// ]));
/// ```
///
/// ## 测试替换
/// 在测试中注入 [MockStorageService]（实现 [IStorageService]），
/// 无需依赖 SharedPreferences，实现完全隔离。
class LocalStorageService implements IStorageService {
  // ── 初始化 ────────────────────────────────────────────────────────────────

  @override
  Future<void> init() => StorageService.init();

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
  }) =>
      StorageService.saveGameState(
        board: board,
        score: score,
        combo: combo,
        bestScore: bestScore,
        maxCombo: maxCombo,
        novelIndex: novelIndex,
        currentNovelId: currentNovelId,
      );

  @override
  Map<String, dynamic>? loadGameState() => StorageService.loadGameState();

  @override
  int loadBestScore() => StorageService.loadBestScore();

  @override
  int loadMaxCombo() => StorageService.loadMaxCombo();

  // ── 书架元数据 ────────────────────────────────────────────────────────────

  @override
  Future<void> saveBookshelf(List<Map<String, dynamic>> shelf) =>
      StorageService.saveBookshelf(shelf);

  @override
  List<Map<String, dynamic>> loadBookshelf() => StorageService.loadBookshelf();

  // ── 阅读进度 ──────────────────────────────────────────────────────────────

  @override
  Future<void> updateReadingRecord(String bookId, int cursor, int total) =>
      StorageService.updateReadingRecord(bookId, cursor, total);

  @override
  Map<String, dynamic> getReadingRecord(String bookId) =>
      StorageService.getReadingRecord(bookId);

  @override
  Future<void> deleteReadingRecord(String bookId) =>
      StorageService.deleteReadingRecord(bookId);

  // ── 当前小说状态 ──────────────────────────────────────────────────────────

  @override
  Future<void> setCurrentNovelId(String? id) =>
      StorageService.setCurrentNovelId(id);

  @override
  String? getCurrentNovelId() => StorageService.getCurrentNovelId();

  @override
  int getCurrentNovelIndex() => StorageService.getCurrentNovelIndex();

  @override
  Future<void> setCurrentNovelIndex(int index) =>
      StorageService.setCurrentNovelIndex(index);

  // ── 书籍正文内容 ──────────────────────────────────────────────────────────

  @override
  Future<void> saveBookContent(
    String bookId, {
    required List<String> lines,
    required List<Map<String, dynamic>> chapters,
  }) =>
      StorageService.saveBookContent(bookId, lines: lines, chapters: chapters);

  @override
  Future<Map<String, dynamic>?> loadBookContent(String bookId) =>
      StorageService.loadBookContent(bookId);

  @override
  Future<void> deleteBookContent(String bookId) =>
      StorageService.deleteBookContent(bookId);

  // ── 全局设置 ──────────────────────────────────────────────────────────────

  @override
  bool getSettingSound() => StorageService.getSettingSound();

  @override
  Future<void> setSettingSound(bool v) => StorageService.setSettingSound(v);

  @override
  bool getSettingStoryTts() => StorageService.getSettingStoryTts();

  @override
  Future<void> setSettingStoryTts(bool v) =>
      StorageService.setSettingStoryTts(v);

  @override
  String getSettingVoice() => StorageService.getSettingVoice();

  @override
  Future<void> setSettingVoice(String v) => StorageService.setSettingVoice(v);

  @override
  int getSettingIdleTimeout() => StorageService.getSettingIdleTimeout();

  @override
  Future<void> setSettingIdleTimeout(int v) =>
      StorageService.setSettingIdleTimeout(v);

  @override
  double getSettingTtsRate() => StorageService.getSettingTtsRate();

  @override
  Future<void> setSettingTtsRate(double v) =>
      StorageService.setSettingTtsRate(v);

  @override
  double getSettingAmbientVol() => StorageService.getSettingAmbientVol();

  @override
  Future<void> setSettingAmbientVol(double v) =>
      StorageService.setSettingAmbientVol(v);

  @override
  bool getSettingAmbientEnabled() => StorageService.getSettingAmbientEnabled();

  @override
  Future<void> setSettingAmbientEnabled(bool v) =>
      StorageService.setSettingAmbientEnabled(v);

  // ── 隐私协议 ──────────────────────────────────────────────────────────────

  @override
  bool hasAgreedPrivacy() => StorageService.hasAgreedPrivacy();

  @override
  Future<void> setHasAgreedPrivacy(bool v) =>
      StorageService.setHasAgreedPrivacy(v);
}
