import 'dart:math' as math;

import 'package:yueyou/features/xiaoyo/domain/xiaoyo_completion_event.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_event.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_listen_events.dart';

/// 将 Reader/TTS 的公开状态转换为稳定、低频、可幂等的 Xiaoyo 事件。
class XiaoyoSignalBridge {
  final Future<void> Function(XiaoyoEvent event) dispatch;
  final DateTime Function() nowUtc;
  String? _lastBookId;
  int? _lastCursor;
  DateTime? _lastProgressAtUtc;
  bool _bookCompletionSent = false;
  String? _lastChapterBookId;
  int? _lastChapterIndex;

  XiaoyoSignalBridge({
    required this.dispatch,
    DateTime Function()? nowUtc,
  }) : nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  /// 接收一次播放游标推进，只在游标真正前进时生成心跳。
  void onPlaybackProgress({
    required String bookId,
    required String bookTitle,
    required int cursor,
    required double progressPercent,
    DateTime? occurredAtUtc,
  }) {
    if (bookId.isEmpty || cursor < 0) return;
    final occurred = (occurredAtUtc ?? nowUtc()).toUtc();
    if (_lastBookId != bookId) {
      _lastBookId = bookId;
      _lastCursor = null;
      _lastProgressAtUtc = occurred;
      _bookCompletionSent = false;
    }
    if (_lastCursor != null && cursor <= _lastCursor!) return;
    final elapsed = _lastProgressAtUtc == null
        ? 1
        : occurred.difference(_lastProgressAtUtc!).inSeconds;
    final advancedSeconds = math.max(1, math.min(90, elapsed));
    _lastCursor = cursor;
    _lastProgressAtUtc = occurred;
    final event = ListenHeartbeat(
      eventId: 'listen:$bookId:$cursor',
      occurredAtUtc: occurred,
      bookId: bookId,
      bookTitle: bookTitle,
      advancedSeconds: advancedSeconds,
      cursor: cursor,
      progressPercent: progressPercent.clamp(0.0, 100.0).toDouble(),
    );
    dispatch(event);
  }

  /// Reader 进入下一章时记录上一章的首次完成事件。
  void onChapterCompleted({
    required String bookId,
    required String chapterKey,
    DateTime? occurredAtUtc,
  }) {
    if (bookId.isEmpty || chapterKey.isEmpty) return;
    final occurred = (occurredAtUtc ?? nowUtc()).toUtc();
    dispatch(
      ChapterCompleted(
        eventId: 'chapter:$bookId:$chapterKey',
        occurredAtUtc: occurred,
        bookId: bookId,
        chapterKey: chapterKey,
      ),
    );
  }

  /// 由桥接层保存章节快照，避免 ChangeNotifier 前后引用相同而丢失差分。
  void onReaderChapter({
    required String bookId,
    required int chapterIndex,
    DateTime? occurredAtUtc,
  }) {
    if (bookId.isEmpty || chapterIndex < 0) return;
    if (_lastChapterBookId != bookId) {
      _lastChapterBookId = bookId;
      _lastChapterIndex = chapterIndex;
      return;
    }
    final previous = _lastChapterIndex;
    _lastChapterIndex = chapterIndex;
    if (previous == null || previous == chapterIndex) return;
    onChapterCompleted(
      bookId: bookId,
      chapterKey: previous.toString(),
      occurredAtUtc: occurredAtUtc,
    );
  }

  /// Reader 首次跨过 95% 时记录完本事件。
  void onBookProgress({
    required String bookId,
    required String bookTitle,
    required double progress,
    DateTime? occurredAtUtc,
  }) {
    if (bookId.isEmpty || progress < 0.95 || _bookCompletionSent) return;
    _bookCompletionSent = true;
    final occurred = (occurredAtUtc ?? nowUtc()).toUtc();
    dispatch(
      BookCompleted(
        eventId: 'book:$bookId:completed',
        occurredAtUtc: occurred,
        bookId: bookId,
        bookTitle: bookTitle,
      ),
    );
  }

  /// 切书后清空只属于桥接层的瞬时游标，不修改 Profile。
  void resetBook() {
    _lastBookId = null;
    _lastCursor = null;
    _lastProgressAtUtc = null;
    _bookCompletionSent = false;
    _lastChapterBookId = null;
    _lastChapterIndex = null;
  }
}
