import 'package:yueyou/features/xiaoyo/domain/xiaoyo_event.dart';

/// 一次有效听读心跳，只携带低频统计所需的元数据。
final class ListenHeartbeat extends XiaoyoEvent {
  final String bookId;
  final String bookTitle;
  final int advancedSeconds;
  final int cursor;
  final double progressPercent;

  const ListenHeartbeat({
    required super.eventId,
    required super.occurredAtUtc,
    required this.bookId,
    required this.bookTitle,
    required this.advancedSeconds,
    required this.cursor,
    required this.progressPercent,
  });
}

/// 第一次完成一个章节的事件。
final class ChapterCompleted extends XiaoyoEvent {
  final String bookId;
  final String chapterKey;

  const ChapterCompleted({
    required super.eventId,
    required super.occurredAtUtc,
    required this.bookId,
    required this.chapterKey,
  });
}
