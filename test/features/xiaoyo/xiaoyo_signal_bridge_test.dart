import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_completion_event.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_event.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_listen_events.dart';
import 'package:yueyou/features/xiaoyo/providers/xiaoyo_signal_bridge.dart';

void main() {
  test('播放游标只生成单调心跳，单次补记最多 90 秒', () {
    final events = <XiaoyoEvent>[];
    final bridge = XiaoyoSignalBridge(
      dispatch: (event) async => events.add(event),
    );
    final first = DateTime.utc(2026, 7, 13, 10);

    bridge.onPlaybackProgress(
      bookId: 'book-1',
      bookTitle: '测试书',
      cursor: 1,
      progressPercent: 1.0,
      occurredAtUtc: first,
    );
    bridge.onPlaybackProgress(
      bookId: 'book-1',
      bookTitle: '测试书',
      cursor: 1,
      progressPercent: 2.0,
      occurredAtUtc: first.add(const Duration(seconds: 30)),
    );
    bridge.onPlaybackProgress(
      bookId: 'book-1',
      bookTitle: '测试书',
      cursor: 2,
      progressPercent: 3.0,
      occurredAtUtc: first.add(const Duration(seconds: 200)),
    );

    expect(events, hasLength(2));
    expect((events.first as ListenHeartbeat).advancedSeconds, 1);
    expect((events.last as ListenHeartbeat).advancedSeconds, 90);
    expect(events.map((event) => event.eventId), <String>[
      'listen:book-1:1',
      'listen:book-1:2',
    ]);
  });

  test('章节和完本事件使用稳定 ID，完本阈值只发一次直到切书', () {
    final events = <XiaoyoEvent>[];
    final bridge = XiaoyoSignalBridge(
      dispatch: (event) async => events.add(event),
    );

    bridge.onChapterCompleted(bookId: 'book-1', chapterKey: '2');
    bridge.onChapterCompleted(bookId: 'book-1', chapterKey: '2');
    bridge.onBookProgress(
      bookId: 'book-1',
      bookTitle: '测试书',
      progress: 0.95,
    );
    bridge.onBookProgress(
      bookId: 'book-1',
      bookTitle: '测试书',
      progress: 1.0,
    );

    expect(events.whereType<ChapterCompleted>(), hasLength(2));
    expect(events.whereType<BookCompleted>(), hasLength(1));
    expect(events.last.eventId, 'book:book-1:completed');

    bridge.resetBook();
    bridge.onBookProgress(
      bookId: 'book-2',
      bookTitle: '第二本书',
      progress: 0.95,
    );
    expect(events.whereType<BookCompleted>(), hasLength(2));
  });

  test('桥接层自行保存章节快照，不依赖 ChangeNotifier 前后引用', () {
    final events = <XiaoyoEvent>[];
    final bridge = XiaoyoSignalBridge(
      dispatch: (event) async => events.add(event),
    );

    bridge.onReaderChapter(bookId: 'book-1', chapterIndex: 0);
    bridge.onReaderChapter(bookId: 'book-1', chapterIndex: 1);
    bridge.onReaderChapter(bookId: 'book-1', chapterIndex: 1);

    expect(events.single.eventId, 'chapter:book-1:0');
  });

  test('2048 高分合并只产生视觉脉冲，不重复触发且不持久化', () {
    var pulseCount = 0;
    final bridge = XiaoyoGameSignalBridge(
      onHighTileMerged: () => pulseCount++,
    );

    bridge
      ..onGameChanged(128)
      ..onGameChanged(128)
      ..onGameChanged(0)
      ..onGameChanged(256);

    expect(pulseCount, 2);
  });
}
