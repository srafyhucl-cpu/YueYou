import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';

/// 全量本地持久化服务
/// 完整复刻旧版 localStorage + LocalDB.js 的所有存储行为
/// 键名与旧版 JS 100% 对齐，保证未来双端迁移零成本
class StorageService {
  // ── 键名（1:1 对应 JS localStorage key）───────────────────────────────────
  static const String _kBestScore = 'bestScore_premium';
  static const String _kMaxCombo = 'maxCombo';
  static const String _kLocalSave = 'local_save_data';
  static const String _kBookshelf = 'local_bookshelf';
  static const String _kReadingRecords = 'reading_records';
  static const String _kCurrentNovelId = 'current_novel_id';
  static const String _kNovelIndex = 'novel_index';
  static const String _kSettingSound = 'setting_sound';
  static const String _kSettingStoryTts = 'setting_story_tts';
  static const String _kSettingVoice = 'setting_voice';
  static const String _kSettingIdleTimeout = 'setting_idle_timeout';
  static const String _kSettingTtsRate = 'setting_tts_rate';
  static const String _kSettingAmbientVol = 'setting_ambient_vol';
  static const String _kSettingAmbientEnabled = 'setting_ambient_enabled';
  static const String _kSettingAmbientStyle = 'setting_ambient_style';
  static const String _kHasAgreedPrivacy = 'has_agreed_privacy';
  static const String _kHasSelectedBook = 'user_has_selected_book';
  static const String _kCurrentChapterIndex = 'current_chapter_index';
  static const String _kSettingAnimationQuality = 'setting_animation_quality';

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// 测试专用：清除 SharedPreferences 单例缓存，使 [init] 可重新初始化
  /// 生产环境禁止调用
  @visibleForTesting
  static void resetForTesting() => _prefs = null;

  static SharedPreferences get _p {
    assert(_prefs != null, 'StorageService.init() 必须在 runApp 前调用');
    return _prefs!;
  }

  // ── 游戏状态 (local_save_data) ────────────────────────────────────────────
  /// 对应 JS saveLocalState() 的完整快照
  static Future<void> saveGameState({
    required List<List<Map<String, dynamic>?>> board,
    required int score,
    required int combo,
    required int bestScore,
    required int maxCombo,
    required int novelIndex,
    String? currentNovelId,
  }) async {
    final st = {
      'board_data': jsonEncode(board),
      'score': score,
      'combo': combo,
      'bestScore': bestScore,
      'maxCombo': maxCombo,
      'novel_index': novelIndex,
      'current_novel_id': currentNovelId,
    };
    await _p.setString(_kLocalSave, jsonEncode(st));
    await _p.setInt(_kBestScore, bestScore);
    await _p.setInt(_kMaxCombo, maxCombo);
    await _p.setInt(_kNovelIndex, novelIndex);
    if (currentNovelId != null) {
      await _p.setString(_kCurrentNovelId, currentNovelId);
    }
  }

  static Map<String, dynamic>? loadGameState() {
    final saved = _p.getString(_kLocalSave);
    if (saved == null) return null;
    try {
      return jsonDecode(saved) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static int loadBestScore() => _p.getInt(_kBestScore) ?? 0;
  static int loadMaxCombo() => _p.getInt(_kMaxCombo) ?? 0;

  // ── 书架元数据 (local_bookshelf) ──────────────────────────────────────────
  static Future<void> saveBookshelf(List<Map<String, dynamic>> shelf) async {
    await _p.setString(_kBookshelf, jsonEncode(shelf));
  }

  static List<Map<String, dynamic>> loadBookshelf() {
    final s = _p.getString(_kBookshelf);
    if (s == null) return [];
    try {
      return (jsonDecode(s) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  // ── 阅读进度 (reading_records / ProgressManager) ─────────────────────────
  static Future<void> updateReadingRecord(
    String bookId,
    int cursor,
    int total,
  ) async {
    if (total <= 0) return;
    final records = _loadReadingRecords();
    final percent = (cursor / total * 100).clamp(0.0, 100.0);
    records[bookId] = {
      'cursor': cursor,
      'total': total,
      'percent': double.parse(percent.toStringAsFixed(2)),
    };
    await _p.setString(_kReadingRecords, jsonEncode(records));
  }

  static Map<String, dynamic> getReadingRecord(String bookId) {
    final records = _loadReadingRecords();
    return records[bookId] as Map<String, dynamic>? ??
        {'cursor': 0, 'total': 1, 'percent': 0.0};
  }

  static Future<void> deleteReadingRecord(String bookId) async {
    final records = _loadReadingRecords();
    records.remove(bookId);
    await _p.setString(_kReadingRecords, jsonEncode(records));
  }

  static Map<String, dynamic> _loadReadingRecords() {
    final s = _p.getString(_kReadingRecords);
    if (s == null) return {};
    try {
      return (jsonDecode(s) as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  static Future<void> setCurrentNovelId(String? id) async {
    if (id == null) {
      await _p.remove(_kCurrentNovelId);
    } else {
      await _p.setString(_kCurrentNovelId, id);
    }
  }

  static String? getCurrentNovelId() => _p.getString(_kCurrentNovelId);

  static int getCurrentNovelIndex() => _p.getInt(_kNovelIndex) ?? 0;

  static int getCurrentChapterIndex() => _p.getInt(_kCurrentChapterIndex) ?? 0;

  static Future<void> setCurrentChapterIndex(int index) async {
    await _p.setInt(_kCurrentChapterIndex, index);
  }

  static Future<void> setCurrentNovelIndex(int index) async {
    await _p.setInt(_kNovelIndex, index);
  }

  // ── 书籍正文内容（替代 IndexedDB LocalDB.js）──────────────────────────────
  static Future<File> _bookFile(String bookId) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/books/$bookId.json');
  }

  static Future<void> saveBookContent(
    String bookId, {
    required List<String> lines,
    required List<Map<String, dynamic>> chapters,
  }) async {
    try {
      final file = await _bookFile(bookId);
      await file.parent.create(recursive: true);
      await file
          .writeAsString(jsonEncode({'lines': lines, 'chapters': chapters}));
    } catch (e, st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'library',
        extra: {'context': 'StorageService.saveBookContent 失败'},
      );
    }
  }

  static Future<Map<String, dynamic>?> loadBookContent(String bookId) async {
    try {
      final file = await _bookFile(bookId);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return null;
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e, st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'library',
        extra: {'context': 'StorageService.loadBookContent 失败'},
      );
      return null;
    }
  }

  static Future<void> deleteBookContent(String bookId) async {
    try {
      final file = await _bookFile(bookId);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  // ── 全局设置 ──────────────────────────────────────────────────────────────
  static bool getSettingSound() => _p.getBool(_kSettingSound) ?? true;
  static Future<void> setSettingSound(bool v) => _p.setBool(_kSettingSound, v);

  static bool getSettingStoryTts() => _p.getBool(_kSettingStoryTts) ?? true;
  static Future<void> setSettingStoryTts(bool v) =>
      _p.setBool(_kSettingStoryTts, v);

  static String getSettingVoice() =>
      _p.getString(_kSettingVoice) ?? 'zh-CN-XiaoxiaoNeural';
  static Future<void> setSettingVoice(String v) =>
      _p.setString(_kSettingVoice, v);

  static int getSettingIdleTimeout() => _p.getInt(_kSettingIdleTimeout) ?? 1;
  static Future<void> setSettingIdleTimeout(int v) =>
      _p.setInt(_kSettingIdleTimeout, v);

  static double getSettingTtsRate() => _p.getDouble(_kSettingTtsRate) ?? 1.0;
  static Future<void> setSettingTtsRate(double v) =>
      _p.setDouble(_kSettingTtsRate, v);

  static double getSettingAmbientVol() =>
      _p.getDouble(_kSettingAmbientVol) ?? 0.5;
  static Future<void> setSettingAmbientVol(double v) =>
      _p.setDouble(_kSettingAmbientVol, v);

  static bool getSettingAmbientEnabled() =>
      _p.getBool(_kSettingAmbientEnabled) ?? true;
  static Future<void> setSettingAmbientEnabled(bool v) =>
      _p.setBool(_kSettingAmbientEnabled, v);

  static String getSettingAmbientStyle() =>
      _p.getString(_kSettingAmbientStyle) ?? 'wuxia';
  static Future<void> setSettingAmbientStyle(String v) =>
      _p.setString(_kSettingAmbientStyle, v);

  static String getSettingAnimationQuality() =>
      _p.getString(_kSettingAnimationQuality) ?? 'auto';
  static Future<void> setSettingAnimationQuality(String v) =>
      _p.setString(_kSettingAnimationQuality, v);

  // ── 隐私协议同意状态 ──────────────────────────────────────────────────────
  static bool hasAgreedPrivacy() => _p.getBool(_kHasAgreedPrivacy) ?? false;
  static Future<void> setHasAgreedPrivacy(bool v) =>
      _p.setBool(_kHasAgreedPrivacy, v);

  // ── 粘性位：用户是否曾主动选择过书籍 ─────────────────────────────────────
  static bool hasSelectedBook() => _p.getBool(_kHasSelectedBook) ?? false;
  static Future<void> setHasSelectedBook(bool v) =>
      _p.setBool(_kHasSelectedBook, v);

  // ── 分章文本缓存（文件路径，非 SharedPreferences）────────────────────────
  static Future<File> _chapterCacheFile(String bookId, int chapterIndex) async {
    final dir = await getApplicationDocumentsDirectory();
    final idx = chapterIndex.toString().padLeft(3, '0');
    return File('${dir.path}/books/chapters/$bookId/$idx.txt');
  }

  static Future<Directory> _chapterCacheDir(String bookId) async {
    final dir = await getApplicationDocumentsDirectory();
    return Directory('${dir.path}/books/chapters/$bookId');
  }

  static Future<void> saveChapterCache(
    String bookId,
    int chapterIndex,
    String text,
  ) async {
    try {
      final file = await _chapterCacheFile(bookId, chapterIndex);
      await file.parent.create(recursive: true);
      await file.writeAsString(text);
    } catch (e, st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'library',
        extra: {'context': 'StorageService.saveChapterCache 失败'},
      );
    }
  }

  static Future<String?> loadChapterCache(
    String bookId,
    int chapterIndex,
  ) async {
    try {
      final file = await _chapterCacheFile(bookId, chapterIndex);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      return content.trim().isEmpty ? null : content;
    } catch (e, st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'library',
        extra: {'context': 'StorageService.loadChapterCache 失败'},
      );
      return null;
    }
  }

  static Future<void> clearChapterCache(String bookId) async {
    try {
      final dir = await _chapterCacheDir(bookId);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e, st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'library',
        extra: {'context': 'StorageService.clearChapterCache 失败'},
      );
    }
  }

  /// LRU 清理：保留 [currentChapterIndex ± keepAround] 范围内文件，其余删除。
  static Future<void> pruneChapterCache(
    String bookId,
    int currentChapterIndex, {
    int keepAround = 3,
  }) async {
    try {
      final dir = await _chapterCacheDir(bookId);
      if (!await dir.exists()) return;
      final keepMin = currentChapterIndex - keepAround;
      final keepMax = currentChapterIndex + keepAround;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.endsWith('.txt')) continue;
        final idx = int.tryParse(name.replaceFirst('.txt', ''));
        if (idx == null) continue;
        if (idx < keepMin || idx > keepMax) await entity.delete();
      }
    } catch (e, st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'library',
        extra: {'context': 'StorageService.pruneChapterCache 失败'},
      );
    }
  }

  // ── 书目录缓存（文件路径）───────────────────────────────────────────────
  static Future<File> _catalogFile(String bookId) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/books/catalogs/${bookId}_catalog.json');
  }

  static Future<void> saveBookCatalog(
    String bookId,
    List<Map<String, dynamic>> chapters,
  ) async {
    try {
      final file = await _catalogFile(bookId);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(chapters));
    } catch (e, st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'library',
        extra: {'context': 'StorageService.saveBookCatalog 失败'},
      );
    }
  }

  static Future<List<Map<String, dynamic>>?> loadBookCatalog(
    String bookId,
  ) async {
    try {
      final file = await _catalogFile(bookId);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return null;
      return (jsonDecode(content) as List).cast<Map<String, dynamic>>();
    } catch (e, st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'library',
        extra: {'context': 'StorageService.loadBookCatalog 失败'},
      );
      return null;
    }
  }
}
