import 'package:yueyou/features/xiaoyo/domain/xiaoyo_event.dart';

/// 一本书第一次达到完本门槛的事件。
final class BookCompleted extends XiaoyoEvent {
  final String bookId;
  final String bookTitle;

  const BookCompleted({
    required super.eventId,
    required super.occurredAtUtc,
    required this.bookId,
    required this.bookTitle,
  });
}
