import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/core/constants/book_constants.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';
import 'package:yueyou/features/library/domain/book_model.dart';
import 'package:yueyou/features/library/services/default_book_service.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';

/// 供 Riverpod 使用的全局书架 Provider
final bookshelfProvider = ChangeNotifierProvider<BookshelfProvider>((ref) {
  final p = BookshelfProvider();
  p.loadFromStorage();
  // 书架中不包含西游记，且用户未主动删除过它 → 自动注入（老用户同样生效）
  final hasDefault = p.hasDefaultBook;
  if (!hasDefault && !StorageService.hasSelectedBook()) {
    Future.microtask(() => p.injectDefaultBookIfNeeded());
  }
  return p;
});

/// 书架状态管理 Provider
/// 完整复刻旧版 local_bookshelf + ProgressManager + LocalDB.js 的业务闭环
class BookshelfProvider with ChangeNotifier {
  List<BookModel> _shelf = [];
  bool _isLoading = false;

  List<BookModel> get shelf => List.unmodifiable(_shelf);
  bool get isLoading => _isLoading;
  bool get isEmpty => _shelf.isEmpty;
  bool get hasDefaultBook =>
      _shelf.any((b) => b.id == BookConstants.defaultBookId);

  /// App 启动时从 SharedPreferences 恢复书架元数据
  void loadFromStorage() {
    final raw = StorageService.loadBookshelf();
    _shelf = raw.map((e) => BookModel.fromJson(e)).toList();
    notifyListeners();
  }

  /// 导入新书 —— 对应 JS fileInput.change → LocalDB.saveBook + localStorage.local_bookshelf
  Future<void> addBook({
    required int id,
    required String title,
    required List<String> lines,
    required List<ChapterModel> chapters,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      // 去重：同名书优先替换（对应 JS existingIndex 逻辑）
      _shelf.removeWhere((b) => b.title == title);

      final book = BookModel(
        id: id,
        title: title,
        total: lines.length,
        chapters: chapters,
      );

      // 新书插在最前面（对应 JS shelf.unshift）
      _shelf.insert(0, book);

      // 持久化正文到文件（对应 LocalDB.saveBook）
      await StorageService.saveBookContent(
        id.toString(),
        lines: lines,
        chapters: chapters.map((c) => c.toJson()).toList(),
      );

      // 持久化书架元数据
      await StorageService.saveBookshelf(
        _shelf.map((b) => b.toJson()).toList(),
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 删除书籍 —— 对应 JS deleteBook：清理书架 + LocalDB + ProgressManager
  ///
  /// **一致性策略：Best-Effort 清理**
  /// 1. 内存状态（_shelf）立即移除，确保 UI 瞬时响应。
  /// 2. 三项持久化清理（书架元数据 / 正文内容 / 阅读记录）独立执行，
  ///    任一失败不影响其他两项，避免单点故障导致数据残留。
  /// 3. 若删除的是当前阅读中的书籍，先级联重置 ReaderProvider 状态。
  Future<void> deleteBook(int id, {ReaderProvider? reader}) async {
    // 级联删除：先重置阅读器，再清数据
    reader?.resetForDeletedBook(id.toString());

    // 删除西游记视为「主动放弃」，设置粘性位防止下次启动再次自动注入
    if (id == BookConstants.defaultBookId) {
      await StorageService.setHasSelectedBook(true);
    }

    _shelf.removeWhere((b) => b.id == id);
    notifyListeners();

    // Best-effort 持久化清理：每步独立 try-catch
    try {
      await StorageService.saveBookshelf(
        _shelf.map((b) => b.toJson()).toList(),
      );
    } catch (e, stack) {
      // coverage:ignore-start
      CyberLogger.captureWarning(
        e,
        stack: stack,
        tag: 'library',
        extra: {'context': '删除书籍后书架元数据持久化失败'},
      );
      // coverage:ignore-end
    }
    try {
      await StorageService.deleteBookContent(id.toString());
    } catch (e, stack) {
      // coverage:ignore-start
      CyberLogger.captureWarning(
        e,
        stack: stack,
        tag: 'library',
        extra: {
          'context': '删除书籍正文内容失败',
          'bookId': id.toString(),
        },
      );
      // coverage:ignore-end
    }
    try {
      await StorageService.deleteReadingRecord(id.toString());
    } catch (e, stack) {
      // coverage:ignore-start
      CyberLogger.captureWarning(
        e,
        stack: stack,
        tag: 'library',
        extra: {
          'context': '删除阅读记录失败',
          'bookId': id.toString(),
        },
      );
      // coverage:ignore-end
    }
  }

  /// 将内置默认书籍（西游记目录）写入书架
  ///
  /// 只写书架元数据和目录缓存，不下载章节正文；
  /// 章节正文由 [ReaderProvider.loadChapter] 按需拉取。
  Future<void> addDefaultBook(List<ChapterModel> catalog) async {
    // 去重：若已存在则跳过
    if (_shelf.any((b) => b.id == BookConstants.defaultBookId)) return;

    final book = BookModel(
      id: BookConstants.defaultBookId,
      title: BookConstants.defaultBookTitle,
      total: BookConstants.defaultTotalChapters,
      chapters: catalog,
    );
    _shelf.insert(0, book);
    notifyListeners();

    // 持久化书架元数据
    await StorageService.saveBookshelf(
      _shelf.map((b) => b.toJson()).toList(),
    );
    // 同步目录缓存（供 DefaultBookService 离线读取）
    await StorageService.saveBookCatalog(
      BookConstants.defaultBookKey,
      catalog.map((c) => c.toJson()).toList(),
    );
  }

  /// 新用户启动链路：拉取目录 → 写书架
  ///
  /// 仅将《西游记》注入书架，不自动加载章节，避免启动阶段
  /// 网络拉取 + Isolate 解析 + TTS pump 同时触发导致 ANR。
  /// 用户点击书籍时再由 LibraryScreen → ReaderProvider.loadChapter 加载。
  Future<void> injectDefaultBookIfNeeded() async {
    // 双重校验（防止并发/重入）
    if (hasDefaultBook || StorageService.hasSelectedBook()) return;

    try {
      final service = DefaultBookService();
      final catalog = await service.getCatalog();
      // getCatalog() 期间可能已 deleteBook(999)，需二次校验防止竞态
      if (hasDefaultBook || StorageService.hasSelectedBook()) return;
      await addDefaultBook(catalog);
    } catch (e, stack) {
      // coverage:ignore-start
      CyberLogger.captureWarning(
        e,
        stack: stack,
        tag: 'library',
        extra: {'context': '默认书籍注入失败'},
      );
      // coverage:ignore-end
    }
  }

  /// 读取书籍正文内容（章节列表 + 行数据）
  Future<Map<String, dynamic>?> loadBookContent(int id) async {
    return StorageService.loadBookContent(id.toString());
  }

  /// 从 ProgressManager.getRecord 获取某书的阅读百分比
  double getReadingPercent(int bookId) {
    final record = StorageService.getReadingRecord(bookId.toString());
    return (record['percent'] as num?)?.toDouble() ?? 0.0;
  }

  /// 从 ProgressManager.getRecord 获取游标
  int getReadingCursor(int bookId) {
    final record = StorageService.getReadingRecord(bookId.toString());
    return (record['cursor'] as num?)?.toInt() ?? 0;
  }

  /// 测试专用：直接注入受控 shelf 数据，避免每个用例都得 mock SharedPreferences。
  ///
  /// 不会触发持久化写入，仅设置内存状态 + notifyListeners。
  @visibleForTesting
  void setShelfForTesting(List<BookModel> shelf) {
    _shelf = List<BookModel>.of(shelf);
    notifyListeners();
  }
}
