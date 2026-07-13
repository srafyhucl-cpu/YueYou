import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/reader/domain/reading_home_view_state.dart';
import 'package:yueyou/features/reader/presentation/screens/reading_home_screen.dart';
import 'package:yueyou/features/reader/providers/reading_home_view_provider.dart';

void main() {
  testWidgets('听读首页七种状态均只展示一个主动作', (tester) async {
    for (final status in ReadingHomeStatus.values) {
      final state = ReadingHomeViewState(
        status: status,
        bookId: status == ReadingHomeStatus.empty ? null : 'book-1',
        bookTitle: '测试书',
        chapterTitle: '第一章',
        currentSentence: '当前测试句段',
        readingProgress: status == ReadingHomeStatus.completed ? 1.0 : 0.4,
        errorMessage:
            status == ReadingHomeStatus.recoverableError ? '音频暂时不可用' : null,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [readingHomeViewProvider.overrideWithValue(state)],
          child: const MaterialApp(home: ReadingHomeScreen()),
        ),
      );

      expect(find.byType(ReadingHomeScreen), findsOneWidget);
      expect(find.text(state.primaryActionLabel), findsOneWidget);
    }
  });
}
