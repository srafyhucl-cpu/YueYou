import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/reader/domain/reading_home_view_state.dart';

void main() {
  test('听读首页固定包含七种互斥状态与唯一主动作', () {
    final states = ReadingHomeStatus.values
        .map((status) => ReadingHomeViewState(status: status))
        .toList();

    expect(states, hasLength(7));
    expect(states.map((state) => state.status).toSet(), hasLength(7));
    expect(
      states.map((state) => state.primaryActionLabel).toSet(),
      containsAll(<String>['导入本地书', '继续听读', '取消缓冲', '暂停听读', '重试播放', '返回书架']),
    );
  });

  test('空状态不携带书籍上下文，完本状态保留当前书籍', () {
    const empty = ReadingHomeViewState.empty();
    const completed = ReadingHomeViewState(
      status: ReadingHomeStatus.completed,
      bookId: 'book-1',
      bookTitle: '测试书',
      readingProgress: 1.0,
    );

    expect(empty.hasBook, isFalse);
    expect(completed.hasBook, isTrue);
    expect(completed.primaryActionLabel, '返回书架');
  });
}
