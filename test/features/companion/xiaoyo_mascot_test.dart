import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/app_shell/presentation/widgets/companion_shell_page.dart';
import 'package:yueyou/features/companion/presentation/widgets/xiaoyo_mascot.dart';

void main() {
  testWidgets('Rive 关闭时直接使用静态回退且不依赖二进制资源', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: XiaoyoMascot(enableRive: false),
      ),
    );

    expect(find.byType(XiaoyoStaticFallback), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(XiaoyoStaticFallback),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Xiaoyo'), findsOneWidget);
  });

  testWidgets('Rive 资源加载失败后仍保留静态回退', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: XiaoyoMascot(
          enableRive: true,
          assetPath: 'assets/rive/missing_for_test.riv',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.byType(XiaoyoStaticFallback), findsOneWidget);
  });

  testWidgets('陪伴页默认不加载 Xiaoyo Rive 资源', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CompanionShellPage()));

    expect(find.text('XIAOYO'), findsOneWidget);
    expect(find.byType(XiaoyoStaticFallback), findsOneWidget);
  });
}
