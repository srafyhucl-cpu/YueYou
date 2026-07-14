/// 作者听校问题的分类。
enum AuthorReviewIssueType {
  /// 错别字或疑似错字。
  typo,

  /// 标点或标点停顿问题。
  punctuation,

  /// 断句、分段或朗读停顿问题。
  sentenceBreak,

  /// 重复文本或重复朗读问题。
  repeatedText,

  /// 人名、地名或专名一致性问题。
  properNoun,

  /// 发音、读音或多音字问题。
  pronunciation,

  /// 暂未归类的问题。
  other,
}

/// 作者听校问题的处理状态。
enum AuthorReviewMarkStatus {
  /// 尚未处理的问题。
  open,

  /// 已确认并处理的问题。
  reviewed,

  /// 已确认但不需要处理的问题。
  ignored,
}

/// 一条只包含定位信息的本地听校标记。
///
/// 标记不保存正文摘录、文件路径、账号或网络信息；字符区间使用导入文本在
/// 当前章节中的稳定偏移，便于重新打开同一本本地书时定位问题。
final class AuthorReviewMark {
  /// 创建一条作者听校标记。
  const AuthorReviewMark({
    required this.id,
    required this.chapterId,
    required this.startOffset,
    required this.endOffset,
    required this.issueType,
    required this.note,
    required this.status,
    required this.createdAtUtc,
    required this.reviewedAtUtc,
  });

  /// 标记的本地稳定 ID。
  final String id;

  /// 章节的本地稳定 ID。
  final String chapterId;

  /// 问题区间的起始偏移，包含该位置。
  final int startOffset;

  /// 问题区间的结束偏移，不包含该位置。
  final int endOffset;

  /// 问题类型。
  final AuthorReviewIssueType issueType;

  /// 用户填写的处理备注，不是正文摘录。
  final String note;

  /// 当前处理状态。
  final AuthorReviewMarkStatus status;

  /// 标记创建时间，统一保存为 UTC。
  final DateTime createdAtUtc;

  /// 最近一次复核时间；开放状态必须为空。
  final DateTime? reviewedAtUtc;

  /// 判断章节内的游标是否落在问题区间内。
  bool containsOffset(int offset) =>
      offset >= startOffset && offset < endOffset;

  /// 返回更新处理状态后的新标记。
  AuthorReviewMark withStatus(
    AuthorReviewMarkStatus nextStatus, {
    DateTime? reviewedAtUtc,
  }) {
    if (nextStatus == AuthorReviewMarkStatus.open && reviewedAtUtc != null) {
      throw ArgumentError('开放状态不能携带复核时间');
    }
    if (nextStatus != AuthorReviewMarkStatus.open && reviewedAtUtc == null) {
      throw ArgumentError('已复核或已忽略状态必须携带复核时间');
    }
    return AuthorReviewMark(
      id: id,
      chapterId: chapterId,
      startOffset: startOffset,
      endOffset: endOffset,
      issueType: issueType,
      note: note,
      status: nextStatus,
      createdAtUtc: createdAtUtc,
      reviewedAtUtc: reviewedAtUtc?.toUtc(),
    );
  }

  /// 将标记编码为不包含正文的本地导出数据。
  Map<String, dynamic> toJson() => {
        'id': id,
        'chapterId': chapterId,
        'startOffset': startOffset,
        'endOffset': endOffset,
        'issueType': issueType.name,
        'note': note,
        'status': status.name,
        'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
        'reviewedAtUtc': reviewedAtUtc?.toUtc().toIso8601String(),
      };

  /// 从本地导出数据恢复标记，结构不完整时直接拒绝。
  factory AuthorReviewMark.fromJson(Map<String, dynamic> json) {
    final createdAtUtc = _readDateTime(json, 'createdAtUtc');
    final reviewedAtUtc = _readOptionalDateTime(json, 'reviewedAtUtc');
    final status = _readEnum(
      AuthorReviewMarkStatus.values,
      json['status'],
      'status',
    );
    if (status == AuthorReviewMarkStatus.open && reviewedAtUtc != null) {
      throw const FormatException('开放状态不能携带复核时间');
    }
    if (status != AuthorReviewMarkStatus.open && reviewedAtUtc == null) {
      throw const FormatException('已复核或已忽略状态缺少复核时间');
    }
    return AuthorReviewMark(
      id: _readRequiredString(json, 'id'),
      chapterId: _readRequiredString(json, 'chapterId'),
      startOffset: _readNonNegativeInt(json, 'startOffset'),
      endOffset: _readNonNegativeInt(json, 'endOffset'),
      issueType: _readEnum(
        AuthorReviewIssueType.values,
        json['issueType'],
        'issueType',
      ),
      note: _readString(json, 'note'),
      status: status,
      createdAtUtc: createdAtUtc,
      reviewedAtUtc: reviewedAtUtc,
    ).._validateRange();
  }

  void _validateRange() {
    if (endOffset <= startOffset) {
      throw const FormatException('endOffset 必须大于 startOffset');
    }
  }
}

String _readRequiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key 必须是非空字符串');
  }
  return value;
}

String _readString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('$key 必须是字符串');
  }
  return value;
}

int _readNonNegativeInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int || value < 0) {
    throw FormatException('$key 必须是非负整数');
  }
  return value;
}

DateTime _readDateTime(Map<String, dynamic> json, String key) {
  final value = json[key];
  final dateTime = value is String ? DateTime.tryParse(value) : null;
  if (dateTime == null) {
    throw FormatException('$key 必须是有效时间');
  }
  return dateTime.toUtc();
}

DateTime? _readOptionalDateTime(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  final dateTime = value is String ? DateTime.tryParse(value) : null;
  if (dateTime == null) {
    throw FormatException('$key 必须是有效时间或 null');
  }
  return dateTime.toUtc();
}

T _readEnum<T extends Enum>(List<T> values, Object? rawValue, String key) {
  if (rawValue is! String) {
    throw FormatException('$key 必须是枚举名称');
  }
  for (final value in values) {
    if (value.name == rawValue) {
      return value;
    }
  }
  throw FormatException('$key 包含未知枚举值：$rawValue');
}
