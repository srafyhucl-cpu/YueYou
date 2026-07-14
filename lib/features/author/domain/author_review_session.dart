import 'author_review_models.dart';

/// 一本本地书的作者听校会话。
///
/// 会话使用不可变更新，保证 UI 或后续 Provider 接入时不会在定位过程中修改
/// 共享列表；导出内容只包含问题定位和用户备注，不包含正文。
final class AuthorReviewSession {
  /// 创建一个作者听校会话。
  AuthorReviewSession({
    required this.bookId,
    Iterable<AuthorReviewMark> marks = const <AuthorReviewMark>[],
  }) : _marks = List<AuthorReviewMark>.unmodifiable(marks) {
    if (bookId.trim().isEmpty) {
      throw ArgumentError.value(bookId, 'bookId', '不能为空');
    }
    _validateMarks(_marks);
    _validateUniqueIds(_marks);
  }

  /// 当前会话对应的本地书籍 ID。
  final String bookId;

  final List<AuthorReviewMark> _marks;

  /// 以只读列表形式返回当前标记。
  List<AuthorReviewMark> get marks => _marks;

  /// 新增标记并返回新会话，重复 ID 会被拒绝。
  AuthorReviewSession addMark(AuthorReviewMark mark) {
    if (_marks.any((candidate) => candidate.id == mark.id)) {
      throw StateError('听校标记 ID 已存在：${mark.id}');
    }
    return AuthorReviewSession(bookId: bookId, marks: [..._marks, mark]);
  }

  /// 更新指定标记的复核状态并返回新会话。
  AuthorReviewSession updateStatus(
    String markId,
    AuthorReviewMarkStatus nextStatus, {
    DateTime? reviewedAtUtc,
  }) {
    final index = _marks.indexWhere((mark) => mark.id == markId);
    if (index < 0) {
      throw StateError('找不到听校标记：$markId');
    }
    final nextMarks = [..._marks];
    nextMarks[index] = nextMarks[index].withStatus(
      nextStatus,
      reviewedAtUtc:
          nextStatus == AuthorReviewMarkStatus.open ? null : reviewedAtUtc,
    );
    return AuthorReviewSession(bookId: bookId, marks: nextMarks);
  }

  /// 按章节和游标定位当前应该展示的标记。
  ///
  /// 返回顺序固定为起始偏移、结束偏移和标记 ID，避免多个重叠标记在不同
  /// 存储顺序下产生不稳定的 UI 结果。
  List<AuthorReviewMark> locateAt({
    required String chapterId,
    required int offset,
  }) {
    if (chapterId.trim().isEmpty) {
      throw ArgumentError.value(chapterId, 'chapterId', '不能为空');
    }
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', '不能为负数');
    }
    final located = _marks
        .where(
          (mark) => mark.chapterId == chapterId && mark.containsOffset(offset),
        )
        .toList()
      ..sort(_compareMarks);
    return List<AuthorReviewMark>.unmodifiable(located);
  }

  /// 导出不包含正文和路径的本地听校报告。
  Map<String, dynamic> toJson() {
    final sortedMarks = [..._marks]..sort(_compareMarksForExport);
    return {
      'schemaVersion': 1,
      'bookId': bookId,
      'marks': sortedMarks.map((mark) => mark.toJson()).toList(),
    };
  }

  /// 从本地听校报告恢复会话，报告结构不完整时直接拒绝。
  factory AuthorReviewSession.fromJson(Map<String, dynamic> json) {
    final rawMarks = json['marks'];
    if (rawMarks is! List<dynamic>) {
      throw const FormatException('marks 必须是数组');
    }
    final marks = <AuthorReviewMark>[];
    for (final rawMark in rawMarks) {
      if (rawMark is! Map) {
        throw const FormatException('marks 中的每一项必须是对象');
      }
      marks.add(
        AuthorReviewMark.fromJson(Map<String, dynamic>.from(rawMark)),
      );
    }
    return AuthorReviewSession(
      bookId: _readSessionBookId(json),
      marks: marks,
    );
  }

  static String _readSessionBookId(Map<String, dynamic> json) {
    final value = json['bookId'];
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('bookId 必须是非空字符串');
    }
    return value;
  }
}

void _validateUniqueIds(List<AuthorReviewMark> marks) {
  final ids = <String>{};
  for (final mark in marks) {
    if (!ids.add(mark.id)) {
      throw StateError('听校标记 ID 已重复：${mark.id}');
    }
  }
}

void _validateMarks(List<AuthorReviewMark> marks) {
  for (final mark in marks) {
    if (mark.id.trim().isEmpty) {
      throw ArgumentError.value(mark.id, 'mark.id', '不能为空');
    }
    if (mark.chapterId.trim().isEmpty) {
      throw ArgumentError.value(mark.chapterId, 'mark.chapterId', '不能为空');
    }
    if (mark.startOffset < 0 || mark.endOffset <= mark.startOffset) {
      throw ArgumentError('听校标记字符区间无效');
    }
    if (mark.status == AuthorReviewMarkStatus.open &&
        mark.reviewedAtUtc != null) {
      throw ArgumentError('开放状态不能携带复核时间');
    }
    if (mark.status != AuthorReviewMarkStatus.open &&
        mark.reviewedAtUtc == null) {
      throw ArgumentError('已复核或已忽略状态必须携带复核时间');
    }
  }
}

int _compareMarks(AuthorReviewMark left, AuthorReviewMark right) {
  final startResult = left.startOffset.compareTo(right.startOffset);
  if (startResult != 0) {
    return startResult;
  }
  final endResult = left.endOffset.compareTo(right.endOffset);
  if (endResult != 0) {
    return endResult;
  }
  return left.id.compareTo(right.id);
}

int _compareMarksForExport(AuthorReviewMark left, AuthorReviewMark right) {
  final chapterResult = left.chapterId.compareTo(right.chapterId);
  if (chapterResult != 0) {
    return chapterResult;
  }
  return _compareMarks(left, right);
}
