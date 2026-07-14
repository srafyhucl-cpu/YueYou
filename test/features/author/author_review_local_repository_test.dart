import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:yueyou/features/author/domain/author_review_models.dart';
import 'package:yueyou/features/author/domain/author_review_session.dart';
import 'package:yueyou/features/author/services/author_review_local_repository.dart';

final _createdAt = DateTime.utc(2026, 7, 14, 6);

AuthorReviewSession _session() {
  return AuthorReviewSession(bookId: 'book-1').addMark(
    AuthorReviewMark(
      id: 'mark-1',
      chapterId: 'chapter-1',
      startOffset: 10,
      endOffset: 12,
      issueType: AuthorReviewIssueType.pronunciation,
      note: '复核专名读音',
      status: AuthorReviewMarkStatus.open,
      createdAtUtc: _createdAt,
      reviewedAtUtc: null,
    ),
  );
}

final class _MemoryDocumentStore implements AuthorReviewDocumentStore {
  String? primary;
  String? backup;
  bool deleted = false;

  @override
  Future<List<String>> readCandidates(String bookId) async => [
        if (primary != null) primary!,
        if (backup != null) backup!,
      ];

  @override
  Future<void> writeAtomically(String bookId, String content) async {
    backup = primary;
    primary = content;
    deleted = false;
  }

  @override
  Future<void> delete(String bookId) async {
    primary = null;
    backup = null;
    deleted = true;
  }
}

void main() {
  test('保存后可以恢复会话，且更新时保留旧备份', () async {
    final store = _MemoryDocumentStore();
    final repository = AuthorReviewLocalRepository(store: store);
    final session = _session();

    await repository.save(session);
    final restored = await repository.load(session.bookId);

    expect(restored?.bookId, 'book-1');
    expect(
        restored?.marks.single.issueType, AuthorReviewIssueType.pronunciation);
    expect(store.backup, isNull);

    await repository.save(
      session.updateStatus(
        'mark-1',
        AuthorReviewMarkStatus.reviewed,
        reviewedAtUtc: DateTime.utc(2026, 7, 14, 7),
      ),
    );
    expect(store.backup, isNotNull);
    expect((await repository.load('book-1'))?.marks.single.status,
        AuthorReviewMarkStatus.reviewed);
  });

  test('主文件损坏时回退到备份，双份损坏时返回 null', () async {
    final store = _MemoryDocumentStore();
    final repository = AuthorReviewLocalRepository(store: store);
    final encoded = _session().toJson();

    store.primary = '{bad json';
    store.backup = _encode(encoded);
    final restored = await repository.load('book-1');

    expect(restored?.marks.single.id, 'mark-1');

    store.backup = '{also bad';
    expect(await repository.load('book-1'), isNull);
  });

  test('删除会话清空主文件和备份', () async {
    final store = _MemoryDocumentStore();
    final repository = AuthorReviewLocalRepository(store: store);

    await repository.save(_session());
    await repository.delete('book-1');

    expect(store.deleted, isTrue);
    expect(await repository.load('book-1'), isNull);
  });

  test('空书籍 ID 在读写删除边界均被拒绝', () async {
    final repository = AuthorReviewLocalRepository(
      store: _MemoryDocumentStore(),
    );

    expect(repository.load(' '), throwsA(isA<ArgumentError>()));
    expect(repository.delete(''), throwsA(isA<ArgumentError>()));
  });
}

String _encode(Map<String, dynamic> value) {
  return jsonEncode(value);
}
