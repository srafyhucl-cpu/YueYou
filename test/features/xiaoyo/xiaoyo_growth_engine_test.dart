import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/xiaoyo/domain/book_realm_mark.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_completion_event.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_growth_engine.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_listen_events.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_profile.dart';

ListenHeartbeat _heartbeat({
  String id = 'heartbeat-1',
  int seconds = 60,
  double progress = 25.0,
  String bookId = 'book-1',
}) =>
    ListenHeartbeat(
      eventId: id,
      occurredAtUtc: DateTime.utc(2026, 7, 13, 10),
      bookId: bookId,
      bookTitle: '测试书',
      advancedSeconds: seconds,
      cursor: 1,
      progressPercent: progress,
    );

void main() {
  final engine = XiaoyoGrowthEngine();

  test('有效听读按分钟累计成长并升级书境印记', () {
    final result = engine.apply(
      XiaoyoProfile.empty(nowUtc: DateTime.utc(2026, 7, 13)),
      _heartbeat(),
    );

    expect(result.applied, isTrue);
    expect(result.profile.validListenSeconds, 60);
    expect(result.profile.bondXp, 1);
    expect(result.profile.bookRealmMarks.single.level, BookRealmMarkLevel.glow);
  });

  test('重复事件不重复计数，非法心跳不进入去重窗口', () {
    final empty = XiaoyoProfile.empty(nowUtc: DateTime.utc(2026, 7, 13));
    final first = engine.apply(empty, _heartbeat());
    final duplicate = engine.apply(first.profile, _heartbeat());
    final invalid = engine.apply(
      first.profile,
      _heartbeat(id: 'heartbeat-invalid', seconds: 91),
    );

    expect(duplicate.applied, isFalse);
    expect(duplicate.profile, first.profile);
    expect(invalid.applied, isFalse);
    expect(invalid.profile.lastAppliedEventIds,
        isNot(contains('heartbeat-invalid')));
  });

  test('章节和完本事件各自幂等，完本会封存印记并解锁首本荣誉', () {
    final empty = XiaoyoProfile.empty(nowUtc: DateTime.utc(2026, 7, 13));
    final chapter = engine.apply(
      empty,
      ChapterCompleted(
        eventId: 'chapter-1',
        occurredAtUtc: DateTime.utc(2026, 7, 13, 11),
        bookId: 'book-1',
        chapterKey: 'chapter-1',
      ),
    );
    final completed = engine.apply(
      chapter.profile,
      BookCompleted(
        eventId: 'book-1-completed',
        occurredAtUtc: DateTime.utc(2026, 7, 13, 11),
        bookId: 'book-1',
        bookTitle: '测试书',
      ),
    );

    expect(chapter.profile.bondXp, 3);
    expect(completed.profile.bondXp, 63);
    expect(completed.profile.bookRealmMarks.single.level,
        BookRealmMarkLevel.sealed);
    expect(completed.unlockedHonorIds, contains('book.first'));
    expect(
      engine
          .apply(
            completed.profile,
            BookCompleted(
              eventId: 'book-1-completed',
              occurredAtUtc: DateTime.utc(2026, 7, 13, 11),
              bookId: 'book-1',
              bookTitle: '测试书',
            ),
          )
          .applied,
      isFalse,
    );
  });

  test('系统时间回拨不会让 Profile 更新时间倒退', () {
    final profile = XiaoyoProfile.empty(
      nowUtc: DateTime.utc(2026, 7, 13, 12),
    );
    final result = engine.apply(
      profile,
      _heartbeat(id: 'old-clock', progress: 50.0),
    );

    expect(result.profile.updatedAtUtc, profile.updatedAtUtc);
  });
}
