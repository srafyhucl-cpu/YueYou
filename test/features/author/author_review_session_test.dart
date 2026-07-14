import 'package:flutter_test/flutter_test.dart';

import 'package:yueyou/features/author/domain/author_review_models.dart';
import 'package:yueyou/features/author/domain/author_review_session.dart';

final _createdAt = DateTime.utc(2026, 7, 14, 6);

AuthorReviewMark _mark({
  String id = 'mark-1',
  String chapterId = 'chapter-1',
  int startOffset = 10,
  int endOffset = 12,
  AuthorReviewIssueType issueType = AuthorReviewIssueType.typo,
}) {
  return AuthorReviewMark(
    id: id,
    chapterId: chapterId,
    startOffset: startOffset,
    endOffset: endOffset,
    issueType: issueType,
    note: '需要复核',
    status: AuthorReviewMarkStatus.open,
    createdAtUtc: _createdAt,
    reviewedAtUtc: null,
  );
}

void main() {
  test('新增标记使用不可变会话并拒绝重复 ID', () {
    final empty = AuthorReviewSession(bookId: 'book-1');
    final first = empty.addMark(_mark());

    expect(empty.marks, isEmpty);
    expect(first.marks, hasLength(1));
    expect(
      () => first.addMark(_mark()),
      throwsA(isA<StateError>()),
    );
  });

  test('问题区间是左闭右开，重叠标记按稳定顺序定位', () {
    final session = AuthorReviewSession(bookId: 'book-1')
        .addMark(_mark(id: 'late', startOffset: 10, endOffset: 15))
        .addMark(_mark(id: 'early', startOffset: 8, endOffset: 12));

    expect(
      session
          .locateAt(chapterId: 'chapter-1', offset: 10)
          .map((mark) => mark.id),
      ['early', 'late'],
    );
    expect(
      session.locateAt(chapterId: 'chapter-1', offset: 15),
      isEmpty,
    );
  });

  test('复核状态更新返回新会话并记录 UTC 时间', () {
    final session = AuthorReviewSession(bookId: 'book-1').addMark(_mark());
    final reviewedAt = DateTime(2026, 7, 14, 15);
    final reviewed = session.updateStatus(
      'mark-1',
      AuthorReviewMarkStatus.reviewed,
      reviewedAtUtc: reviewedAt,
    );

    expect(session.marks.single.status, AuthorReviewMarkStatus.open);
    expect(reviewed.marks.single.status, AuthorReviewMarkStatus.reviewed);
    expect(reviewed.marks.single.reviewedAtUtc, reviewedAt.toUtc());
  });

  test('导出只包含定位数据和备注，不包含正文、路径或账号', () {
    final session = AuthorReviewSession(bookId: 'book-1').addMark(_mark());

    final exported = session.toJson();
    final mark = (exported['marks'] as List<dynamic>).single as Map;

    expect(exported['bookId'], 'book-1');
    expect(mark['chapterId'], 'chapter-1');
    expect(mark.containsKey('note'), isTrue);
    expect(mark.containsKey('excerpt'), isFalse);
    expect(mark.containsKey('content'), isFalse);
    expect(mark.containsKey('path'), isFalse);
    expect(mark.containsKey('accountId'), isFalse);
  });

  test('导出数据可以往返恢复，非法区间直接拒绝', () {
    final session = AuthorReviewSession(bookId: 'book-1').addMark(_mark());
    final restored = AuthorReviewSession.fromJson(session.toJson());

    expect(restored.bookId, 'book-1');
    expect(restored.marks.single.id, 'mark-1');
    expect(restored.marks.single.issueType, AuthorReviewIssueType.typo);
    expect(
      () => AuthorReviewSession(bookId: 'book-1').addMark(
        _mark(id: 'invalid', startOffset: 5, endOffset: 5),
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => AuthorReviewMark.fromJson({
        ..._mark().toJson(),
        'startOffset': 5,
        'endOffset': 5,
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
