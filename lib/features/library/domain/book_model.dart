import '../../../core/utils/safe_string.dart';

/// 书架书目模型
/// 对应旧版 JS local_bookshelf 数组中的单个对象: { id, title, total, cursor }
class BookModel {
  final int id;
  final String title;
  final int total;
  final int cursor;
  final List<ChapterModel> chapters;

  const BookModel({
    required this.id,
    required this.title,
    required this.total,
    this.cursor = 0,
    this.chapters = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'total': total,
        'cursor': cursor,
        'chapters': chapters.map((c) => c.toJson()).toList(),
      };

  factory BookModel.fromJson(Map<String, dynamic> json) => BookModel(
        id: json['id'] as int,
        title: json['title'] as String,
        total: (json['total'] as num?)?.toInt() ?? 0,
        cursor: (json['cursor'] as num?)?.toInt() ?? 0,
        chapters: (json['chapters'] as List<dynamic>? ?? [])
            .map((e) => ChapterModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  BookModel copyWith({int? cursor, List<ChapterModel>? chapters}) => BookModel(
        id: id,
        title: title,
        total: total,
        cursor: cursor ?? this.cursor,
        chapters: chapters ?? this.chapters,
      );

  /// 去掉 .txt 后缀的展示标题（对应 JS cleanTitle 逻辑）
  String get displayTitle =>
      title.replaceAll(RegExp(r'\.txt$', caseSensitive: false), '');

  /// 封面首字（对应 JS coverChar）
  String get coverChar =>
      displayTitle.isNotEmpty ? safeSubstring(displayTitle, 0, 1) : '?';
}

/// 章节索引模型
/// 对应旧版 LocalDB.js chapters 数组中的对象: { title, lineIndex }
class ChapterModel {
  final String title;
  final int lineIndex;

  const ChapterModel({required this.title, required this.lineIndex});

  Map<String, dynamic> toJson() => {'title': title, 'lineIndex': lineIndex};

  factory ChapterModel.fromJson(Map<String, dynamic> json) => ChapterModel(
        title: json['title'] as String,
        lineIndex: (json['lineIndex'] as num).toInt(),
      );
}
