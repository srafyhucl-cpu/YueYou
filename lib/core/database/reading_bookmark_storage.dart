import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';

/// 阅读书签的独立序列化存储。
///
/// 只处理书签键的读写与格式清洗，不参与阅读游标或业务状态编排。
class ReadingBookmarkStorage {
  const ReadingBookmarkStorage._();

  static const String _key = 'reading_bookmarks';

  /// 读取指定书籍的书签行号，损坏或不存在时返回空列表。
  static List<int> get(SharedPreferences prefs, String bookId) {
    final bookmarks = _load(prefs)[bookId];
    if (bookmarks is! List) return <int>[];
    return bookmarks
        .whereType<num>()
        .map((value) => value.toInt())
        .where((value) => value >= 0)
        .toSet()
        .toList()
      ..sort();
  }

  /// 保存指定书籍的书签行号，去重并排序后写入本地。
  static Future<void> set(
    SharedPreferences prefs,
    String bookId,
    List<int> lineIndexes,
  ) async {
    final allBookmarks = _load(prefs);
    final normalized = lineIndexes.where((value) => value >= 0).toSet().toList()
      ..sort();
    allBookmarks[bookId] = normalized;
    await prefs.setString(_key, jsonEncode(allBookmarks));
  }

  /// 删除指定书籍的全部书签。
  static Future<void> delete(SharedPreferences prefs, String bookId) async {
    final allBookmarks = _load(prefs);
    allBookmarks.remove(bookId);
    await prefs.setString(_key, jsonEncode(allBookmarks));
  }

  static Map<String, dynamic> _load(SharedPreferences prefs) {
    final value = prefs.getString(_key);
    if (value == null) return <String, dynamic>{};
    try {
      return (jsonDecode(value) as Map).cast<String, dynamic>();
    } catch (e, st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'reader',
        extra: {'context': '书签 JSON 解析失败，已按空书签处理'},
      );
      return <String, dynamic>{};
    }
  }
}
