import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/xiaoyo/domain/book_realm_mark.dart';
import 'package:yueyou/features/xiaoyo/domain/honor_record.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_profile.dart';
import 'package:yueyou/features/xiaoyo/presentation/widgets/xiaoyo_profile_summary.dart';

void main() {
  testWidgets('本地 Profile 摘要展示印记和荣誉，不提供写入控件', (tester) async {
    final profile = XiaoyoProfile.empty(
      nowUtc: DateTime.utc(2026, 7, 13),
    ).copyWith(
      validListenSeconds: 120,
      bookRealmMarks: [
        BookRealmMark(
          bookId: 'book-1',
          titleSnapshot: '测试书',
          level: BookRealmMarkLevel.glow,
          completedAtUtc: null,
          validListenSeconds: 120,
          visualSeed: 1,
        ),
      ],
      unlockedHonors: [
        HonorRecord(
          honorId: 'book.first',
          unlockedAtUtc: DateTime.utc(2026, 7, 13),
          sourceEventId: 'book-1-completed',
          rulesVersion: 'v1',
          resourceId: 'base',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: XiaoyoProfileSummary(profile: profile),
          ),
        ),
      ),
    );

    expect(find.text('测试书'), findsOneWidget);
    expect(find.text('微光'), findsOneWidget);
    expect(find.text('book.first'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
  });
}
