import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/xiaoyo/domain/bookscape_preview.dart';
import 'package:yueyou/features/xiaoyo/presentation/widgets/xiaoyo_bookscape_preview.dart';

void main() {
  test('书境目录只包含免费基础项和待实验主题预览项', () {
    expect(XiaoyoBookscapePreviews.all, hasLength(2));
    expect(XiaoyoBookscapePreviews.free.previewOnly, isFalse);
    expect(XiaoyoBookscapePreviews.paidPreview.previewOnly, isTrue);
    expect(
      XiaoyoBookscapePreviews.paidPreview.description,
      contains('尚未开放购买'),
    );
  });

  testWidgets('书境预览展示同一进度下的两种表现且没有购买控件', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: XiaoyoBookscapePreview()),
        ),
      ),
    );

    expect(find.text('书境效果对比'), findsOneWidget);
    expect(find.text('基础书境'), findsNWidgets(2));
    expect(find.text('主题预览'), findsOneWidget);
    expect(find.text('纸页台座'), findsOneWidget);
    expect(find.text('岭南雨驿'), findsNothing);
    expect(find.text('免费可用'), findsOneWidget);
    await tester.tap(find.text('主题预览'));
    await tester.pumpAndSettle();
    expect(find.text('岭南雨驿'), findsOneWidget);
    expect(find.text('仅预览'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });
}
