/// 书境印记的四级进度。
enum BookRealmMarkLevel {
  none(0.0),
  glow(25.0),
  formed(50.0),
  resonance(75.0),
  sealed(95.0);

  final double thresholdPercent;

  const BookRealmMarkLevel(this.thresholdPercent);
}

/// 一本书对应的本地书境印记，不包含正文或路径。
final class BookRealmMark {
  final String bookId;
  final String titleSnapshot;
  final BookRealmMarkLevel level;
  final DateTime? completedAtUtc;
  final int validListenSeconds;
  final int visualSeed;

  const BookRealmMark({
    required this.bookId,
    required this.titleSnapshot,
    required this.level,
    required this.completedAtUtc,
    required this.validListenSeconds,
    required this.visualSeed,
  });

  BookRealmMark copyWith({
    String? titleSnapshot,
    BookRealmMarkLevel? level,
    DateTime? completedAtUtc,
    int? validListenSeconds,
  }) =>
      BookRealmMark(
        bookId: bookId,
        titleSnapshot: titleSnapshot ?? this.titleSnapshot,
        level: level ?? this.level,
        completedAtUtc: completedAtUtc ?? this.completedAtUtc,
        validListenSeconds: validListenSeconds ?? this.validListenSeconds,
        visualSeed: visualSeed,
      );

  Map<String, dynamic> toJson() => {
        'bookId': bookId,
        'titleSnapshot': titleSnapshot,
        'level': level.name,
        'completedAtUtc': completedAtUtc?.toUtc().toIso8601String(),
        'validListenSeconds': validListenSeconds,
        'visualSeed': visualSeed,
      };

  factory BookRealmMark.fromJson(Map<String, dynamic> json) {
    final levelName = json['level'] as String? ?? 'none';
    final level = BookRealmMarkLevel.values.firstWhere(
      (candidate) => candidate.name == levelName,
      orElse: () => BookRealmMarkLevel.none,
    );
    final completed =
        DateTime.tryParse(json['completedAtUtc'] as String? ?? '');
    return BookRealmMark(
      bookId: json['bookId'] as String? ?? '',
      titleSnapshot: json['titleSnapshot'] as String? ?? '',
      level: level,
      completedAtUtc: completed?.toUtc(),
      validListenSeconds: (json['validListenSeconds'] as num?)?.toInt() ?? 0,
      visualSeed: (json['visualSeed'] as num?)?.toInt() ?? 0,
    );
  }
}
