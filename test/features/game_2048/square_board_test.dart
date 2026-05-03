import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';
import 'package:yueyou/features/game_2048/domain/tile_model.dart';
import 'package:yueyou/features/game_2048/presentation/widgets/square_board.dart';
import 'package:yueyou/features/game_2048/providers/game_provider.dart';
import 'package:yueyou/main.dart';
import '../../utils/test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await initializeTestEnvironment();
  });

  TtsEngineService? activeTts;

  tearDown(() {
    activeTts?.dispose();
    activeTts = null;
  });

  Widget createTestableWidget(GameProvider provider) {
    final settings = makeSettings();
    final ttsEngine = makeTtsEngine(settings);
    activeTts = ttsEngine;

    return ProviderScope(
      overrides: [
        gameProvider.overrideWith((ref) => provider),
        settingsProvider.overrideWith((ref) => settings),
        ttsEngineProvider.overrideWith((ref) => ttsEngine),
      ],
      child: MaterialApp(
        navigatorKey: globalNavigatorKey,
        home: const Scaffold(body: SquareBoard()),
      ),
    );
  }

  group('SquareBoard Widget Tests', () {
    testWidgets('渲染基础棋盘网格', (tester) async {
      final provider = GameProvider(
        autoLoadState: false,
        persistDebounceDuration: Duration.zero,
      )..soundEnabled = false;

      await tester.pumpWidget(createTestableWidget(provider));
      await tester.pump();

      // 验证 16 个背景格子
      expect(find.byType(Stack), findsWidgets);
    });

    testWidgets('渲染方块及其数值', (tester) async {
      final provider = GameProvider(
        autoLoadState: false,
        persistDebounceDuration: Duration.zero,
      )..soundEnabled = false;

      provider.setStateForTesting(
        board: [
          [const TileModel(id: 1, value: 2), null, null, null],
          [null, const TileModel(id: 2, value: 2048), null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );

      await tester.pumpWidget(createTestableWidget(provider));
      await tester.pump();

      expect(find.text('2'), findsOneWidget);
      expect(find.text('2048'), findsOneWidget);
    });

    testWidgets('手势滑动触发 move', (tester) async {
      final provider = GameProvider(
        autoLoadState: false,
        persistDebounceDuration: Duration.zero,
      )..soundEnabled = false;

      provider.setStateForTesting(
        board: [
          [null, null, null, const TileModel(id: 1, value: 2)],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );

      await tester.pumpWidget(createTestableWidget(provider));
      await tester.pump();

      // 模拟向左滑动
      final boardGesture = find.byKey(const ValueKey('square_board_gesture'));
      await tester.drag(boardGesture, const Offset(-100, 0));
      await tester.pump(const Duration(milliseconds: 500));

      // 检查方块是否移动到左边
      expect(provider.board[0][0]?.value, equals(2));
    });

    testWidgets('游戏结束显示弹窗并可点击复制战绩', (tester) async {
      final provider = GameProvider(
        autoLoadState: false,
        persistDebounceDuration: Duration.zero,
      )..soundEnabled = false;

      provider.setStateForTesting(
        isOver: true,
        score: 5000,
        board: [
          [const TileModel(id: 1, value: 1024), null, null, null],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );

      await tester.pumpWidget(createTestableWidget(provider));
      // RainEffect 循环动画会阻止 pumpAndSettle
      await tester.pump(const Duration(milliseconds: 100));

      // 验证弹窗内容
      expect(find.text('游戏结束'), findsOneWidget);
      expect(find.text('5000'), findsWidgets);
      expect(find.text('大师'), findsOneWidget);

      // 点击分享区域的复制按钮
      final copyBtn = find.text('复制');
      expect(copyBtn, findsOneWidget);
      await tester.tap(copyBtn);
      // CyberToast 有 300ms 进场动画，pump 500ms 确保完全显示
      await tester.pump(const Duration(milliseconds: 500));

      // 验证提示复制成功的 SnackBar
      expect(find.text('战绩已复制到剪贴板'), findsOneWidget);

      // 🧹 等待 Toast 自动消失，避免 Pending Timers 错误
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('点击重新开始按钮重置游戏', (tester) async {
      final provider = GameProvider(
        autoLoadState: false,
        persistDebounceDuration: Duration.zero,
      )..soundEnabled = false;

      provider.setStateForTesting(isOver: true);

      await tester.pumpWidget(createTestableWidget(provider));
      await tester.pump(const Duration(milliseconds: 100));

      final resetBtn = find.text('重新开始');
      expect(resetBtn, findsOneWidget);
      await tester.tap(resetBtn);
      await tester.pump(const Duration(milliseconds: 500));

      expect(provider.isOver, isFalse);
      expect(find.text('游戏结束'), findsNothing);
    });
  });
}
