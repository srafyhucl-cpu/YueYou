import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';
import 'package:yueyou/features/author/domain/author_review_repository.dart';
import 'package:yueyou/features/author/domain/author_review_session.dart';

/// 作者听校文档存储的可替换边界，便于不触碰真实文件系统进行测试。
abstract interface class AuthorReviewDocumentStore {
  /// 按书籍 ID 返回主文件和备份文件的原始内容，主文件排在前面。
  Future<List<String>> readCandidates(String bookId);

  /// 以主文件、备份文件和临时文件顺序原子写入内容。
  Future<void> writeAtomically(String bookId, String content);

  /// 删除指定书籍的所有本地听校文件。
  Future<void> delete(String bookId);
}

/// 作者听校会话的本地文件仓储。
final class AuthorReviewLocalRepository implements AuthorReviewRepository {
  /// 创建仓储，可注入文档存储替身。
  AuthorReviewLocalRepository({
    AuthorReviewDocumentStore? store,
  }) : _store = store ?? AuthorReviewFileStore();

  final AuthorReviewDocumentStore _store;

  @override
  Future<AuthorReviewSession?> load(String bookId) async {
    _validateBookId(bookId);
    try {
      final candidates = await _store.readCandidates(bookId);
      for (final raw in candidates) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('作者听校文件根节点不是对象');
          }
          return AuthorReviewSession.fromJson(decoded);
        } on Object catch (error, stackTrace) {
          CyberLogger.captureWarning(
            error,
            stack: stackTrace,
            tag: 'reader',
            extra: {'context': '作者听校文件结构无效，尝试下一份备份'},
          );
        }
      }
      return null;
    } on Object catch (error, stackTrace) {
      CyberLogger.captureWarning(
        error,
        stack: stackTrace,
        tag: 'reader',
        extra: {'context': '作者听校文件读取失败'},
      );
      return null;
    }
  }

  @override
  Future<void> save(AuthorReviewSession session) async {
    try {
      await _store.writeAtomically(
        session.bookId,
        jsonEncode(session.toJson()),
      );
    } on Object catch (error, stackTrace) {
      CyberLogger.captureWarning(
        error,
        stack: stackTrace,
        tag: 'reader',
        extra: {'context': '作者听校文件原子写入失败'},
      );
      rethrow;
    }
  }

  @override
  Future<void> delete(String bookId) async {
    _validateBookId(bookId);
    try {
      await _store.delete(bookId);
    } on Object catch (error, stackTrace) {
      CyberLogger.captureWarning(
        error,
        stack: stackTrace,
        tag: 'reader',
        extra: {'context': '作者听校文件删除失败'},
      );
      rethrow;
    }
  }
}

/// 使用应用文档目录保存作者听校文件的实现。
final class AuthorReviewFileStore implements AuthorReviewDocumentStore {
  /// 创建文件存储，可注入应用文档目录定位器。
  AuthorReviewFileStore({
    Future<Directory> Function()? documentsDirectory,
  }) : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory;

  static const String _directoryName = 'author_review';

  final Future<Directory> Function() _documentsDirectory;

  @override
  Future<List<String>> readCandidates(String bookId) async {
    final files = await _files(bookId);
    final contents = <String>[];
    for (final file in <File>[files.primary, files.backup]) {
      if (await file.exists()) {
        contents.add(await file.readAsString());
      }
    }
    return contents;
  }

  @override
  Future<void> writeAtomically(String bookId, String content) async {
    final files = await _files(bookId);
    await files.temp.writeAsString(content, flush: true);
    if (await files.primary.exists()) {
      if (await files.backup.exists()) {
        await files.backup.delete();
      }
      await files.primary.copy(files.backup.path);
      await files.primary.delete();
    }
    await files.temp.rename(files.primary.path);
  }

  @override
  Future<void> delete(String bookId) async {
    final files = await _files(bookId);
    for (final file in <File>[files.primary, files.backup, files.temp]) {
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<_AuthorReviewFiles> _files(String bookId) async {
    final documents = await _documentsDirectory();
    final directory = Directory('${documents.path}/$_directoryName');
    await directory.create(recursive: true);
    final key = _storageKey(bookId);
    return _AuthorReviewFiles(
      primary: File('${directory.path}/$key.json'),
      backup: File('${directory.path}/$key.json.bak'),
      temp: File('${directory.path}/$key.json.tmp'),
    );
  }

  String _storageKey(String bookId) =>
      base64Url.encode(utf8.encode(bookId)).replaceAll('=', '');
}

final class _AuthorReviewFiles {
  const _AuthorReviewFiles({
    required this.primary,
    required this.backup,
    required this.temp,
  });

  final File primary;
  final File backup;
  final File temp;
}

void _validateBookId(String bookId) {
  if (bookId.trim().isEmpty) {
    throw ArgumentError.value(bookId, 'bookId', '不能为空');
  }
}
