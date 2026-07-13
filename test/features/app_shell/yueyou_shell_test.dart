import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/core/config/feature_flags.dart';
import 'package:yueyou/features/app_shell/presentation/yueyou_shell.dart';
import 'package:yueyou/features/app_shell/providers/app_shell_provider.dart';

void main() {
  test('阶段性功能开关默认全部关闭', () {
    expect(FeatureFlags.readingFirstShell, isFalse);
    expect(FeatureFlags.xiaoyoV2, isFalse);
    expect(FeatureFlags.xiaoyoValueSystem, isFalse);
    expect(FeatureFlags.commercePreview, isFalse);
    expect(FeatureFlags.xiaoyo3d, isFalse);
  });

  testWidgets('三根导航只切换页签并保留 IndexedStack 页面', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: YueYouShell(
            showMiniPlayer: false,
            pages: const [
              Text('听读页面'),
              Text('书架页面'),
              Text('陪伴页面'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('听读页面'), findsOneWidget);
    expect(find.byType(IndexedStack), findsOneWidget);

    await tester.tap(find.text('书架'));
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(YueYouShell)),
    );
    expect(container.read(appShellTabProvider), AppShellTab.library);
    expect(find.text('书架'), findsOneWidget);
    expect(find.text('书架页面'), findsOneWidget);
  });
}
