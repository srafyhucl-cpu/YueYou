import 'package:flutter/material.dart';

import '../../../core/database/storage_service.dart';
import '../domain/book_model.dart';

/// 书架状态管理 Provider
/// 完整复刻旧版 local_bookshelf + ProgressManager + LocalDB.js 的业务闭环
class BookshelfProvider with ChangeNotifier {
  List<BookModel> _shelf = [];
  bool _isLoading = false;

  List<BookModel> get shelf => List.unmodifiable(_shelf);
  bool get isLoading => _isLoading;
  bool get isEmpty => _shelf.isEmpty;

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
          _shelf.map((b) => b.toJson()).toList());
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 删除书籍 —— 对应 JS deleteBook：清理书架 + LocalDB + ProgressManager
  Future<void> deleteBook(int id) async {
    _shelf.removeWhere((b) => b.id == id);
    await Future.wait([
      StorageService.saveBookshelf(_shelf.map((b) => b.toJson()).toList()),
      StorageService.deleteBookContent(id.toString()),
      StorageService.deleteReadingRecord(id.toString()),
    ]);
    notifyListeners();
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
}
