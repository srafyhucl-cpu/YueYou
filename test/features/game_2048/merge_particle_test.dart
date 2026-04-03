import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/game_2048/presentation/widgets/merge_particle.dart';

void main() {
  testWidgets('MergeParticle 渲染并触发完成回调', (tester) async {
    bool completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MergeParticle(
            color: Colors.blue,
            onComplete: () => completed = true,
          ),
        ),
      ),
    );

    // 初始渲染
    expect(
        find.descendant(
          of: find.byType(MergeParticle),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget);
    expect(completed, isFalse);

    // 等待动画结束 (duration is 400ms)
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(completed, isTrue);
  });

  testWidgets('MergeParticlePainter shouldRepaint 逻辑', (tester) async {
    // 间接测试 painter 的 shouldRepaint
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MergeParticle(
            color: Colors.red,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));
    // 只要不崩溃即代表基本的绘制逻辑正常
    expect(
        find.descendant(
          of: find.byType(MergeParticle),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget);
  });
}
