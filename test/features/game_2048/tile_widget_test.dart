import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/features/game_2048/presentation/widgets/merge_particle.dart';
import 'package:yueyou/features/game_2048/presentation/widgets/tile_widget.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 120,
            height: 120,
            child: child,
          ),
        ),
      ),
    );
  }

  Future<void> pumpChangedTile(
    WidgetTester tester, {
    required int oldValue,
    required int newValue,
  }) async {
    await tester.pumpWidget(wrap(TileWidget(value: oldValue)));
    await tester.pump();
    await tester.pumpWidget(wrap(TileWidget(value: newValue)));
    await tester.pump();
  }

  group('TileWidget', () {
    testWidgets('value 为 0 时不渲染内容', (tester) async {
      await tester.pumpWidget(wrap(const TileWidget(value: 0)));

      expect(find.byType(SizedBox), findsWidgets);
      expect(find.text('0'), findsNothing);
      expect(find.byType(MergeParticle), findsNothing);
    });

    testWidgets('正常渲染数字文本', (tester) async {
      await tester.pumpWidget(wrap(const TileWidget(value: 2)));
      await tester.pump();

      expect(find.text('2'), findsOneWidget);
      expect(find.byType(MergeParticle), findsNothing);
    });

    testWidgets('升级时触发粒子效果并在动画结束后消失', (tester) async {
      await tester.pumpWidget(wrap(const TileWidget(value: 2)));
      await tester.pump();

      expect(find.text('2'), findsOneWidget);
      expect(find.byType(MergeParticle), findsNothing);

      await tester.pumpWidget(wrap(const TileWidget(value: 4)));
      await tester.pump();

      expect(find.text('4'), findsOneWidget);
      expect(find.byType(MergeParticle), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(MergeParticle), findsNothing);
    });

    testWidgets('更大数字分支可以正常渲染', (tester) async {
      await tester.pumpWidget(wrap(const TileWidget(value: 2048)));
      await tester.pump();

      expect(find.text('2048'), findsOneWidget);
    });

    testWidgets('超过 2048 的默认分支可以正常渲染', (tester) async {
      await tester.pumpWidget(wrap(const TileWidget(value: 4096)));
      await tester.pump();

      expect(find.text('4096'), findsOneWidget);
    });

    testWidgets('64 档位粒子颜色为 neonPurple', (tester) async {
      await pumpChangedTile(tester, oldValue: 16, newValue: 32);

      final particle = tester.widget<MergeParticle>(find.byType(MergeParticle));
      expect(particle.color, CyberColors.neonPurple);
    });

    testWidgets('256 档位粒子颜色为 hotPink', (tester) async {
      await pumpChangedTile(tester, oldValue: 64, newValue: 128);

      final particle = tester.widget<MergeParticle>(find.byType(MergeParticle));
      expect(particle.color, CyberColors.hotPink);
    });

    testWidgets('1024 档位粒子颜色为 neonCyan', (tester) async {
      await pumpChangedTile(tester, oldValue: 256, newValue: 512);

      final particle = tester.widget<MergeParticle>(find.byType(MergeParticle));
      expect(particle.color, CyberColors.neonCyan);
    });
  });
}
