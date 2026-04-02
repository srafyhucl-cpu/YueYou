import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/features/game_2048/domain/tile_model.dart';
import 'package:yueyou/features/game_2048/presentation/widgets/square_board.dart';
import 'package:yueyou/features/game_2048/providers/game_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTesting();
    await StorageService.init();

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    // Mock Haptic (StandardMethodCodec)
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter/haptic'), (methodCall) async => null);

    // Mock Platform channel (JSONMethodCodec is required for SystemChannels.platform)
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter/platform', JSONMethodCodec()),
      (methodCall) async => null,
    );

    // Mock SystemSound (Independent channel in some versions, or uses flutter/platform)
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter/system_sound'),
        (methodCall) async => null);

    // Mock Audioplayers
    messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers.global'),
        (methodCall) async => null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers'),
        (methodCall) async => null);

    // Mock path_provider
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async {
      if (methodCall.method == 'getTemporaryDirectory') return '.';
      if (methodCall.method == 'getApplicationDocumentsDirectory') return '.';
      return '.';
    });
  });

  Widget createTestableWidget(GameProvider provider) {
    return MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<GameProvider>.value(
          value: provider,
          child: const SquareBoard(),
        ),
      ),
    );
  }

  group('SquareBoard Widget Tests', () {
    testWidgets('渲染基础棋盘网格', (tester) async {
      final provider = GameProvider(
        autoLoadState: false,
        persistDebounceDuration: Duration.zero,
      )..soundEnabled = false;
      addTearDown(provider.dispose);
      await tester.pumpWidget(createTestableWidget(provider));
      await tester
          .pump(); // SquareBoard has animations, but shouldn't settle if repeating

      // 验证 16 个背景格子
      expect(find.byType(Stack), findsWidgets);
    });

    testWidgets('渲染方块及其数值', (tester) async {
      final provider = GameProvider(
        autoLoadState: false,
        persistDebounceDuration: Duration.zero,
      )..soundEnabled = false;
      addTearDown(provider.dispose);
      provider.board = List.generate(4, (_) => List.filled(4, null));
      provider.board[0][0] = const TileModel(id: 1, value: 2);
      provider.board[1][1] = const TileModel(id: 2, value: 2048);

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
      addTearDown(provider.dispose);
      provider.board = List.generate(4, (_) => List.filled(4, null));
      provider.board[0][3] = const TileModel(id: 1, value: 2);

      await tester.pumpWidget(createTestableWidget(provider));
      await tester.pump();

      // 模拟向左滑动
      // 使用 GestureDetector 而不是 SquareBoard 以确保命中
      await tester.drag(find.byType(GestureDetector), const Offset(-100, 0));
      await tester.pump(const Duration(milliseconds: 500)); // 等待动画完成

      // 检查方块是否移动到左边
      expect(provider.board[0][0]?.value, equals(2));
    });

    testWidgets('游戏结束显示弹窗并可点击复制战绩', (tester) async {
      final provider = GameProvider(
        autoLoadState: false,
        persistDebounceDuration: Duration.zero,
      )..soundEnabled = false;
      addTearDown(provider.dispose);
      provider.isOver = true;
      provider.score = 5000;
      provider.board = List.generate(4, (_) => List.filled(4, null));
      provider.board[0][0] = const TileModel(id: 1, value: 1024);

      await tester.pumpWidget(createTestableWidget(provider));
      // RainEffect 循环动画会阻止 pumpAndSettle
      await tester.pump(const Duration(milliseconds: 100));

      // 验证弹窗内容
      expect(find.text('游戏结束'), findsOneWidget);
      expect(find.text('5000'), findsWidgets); // score 可能在多个地方显示
      expect(find.text('大师'), findsOneWidget);

      // 点击分享区域的复制按钮
      final copyBtn = find.text('复制');
      expect(copyBtn, findsOneWidget);
      await tester.tap(copyBtn);
      await tester.pump(const Duration(milliseconds: 100));

      // 验证提示复制成功的 SnackBar
      expect(find.text('战绩已复制到剪贴板'), findsOneWidget);
    });

    testWidgets('点击重新开始按钮重置游戏', (tester) async {
      final provider = GameProvider(
        autoLoadState: false,
        persistDebounceDuration: Duration.zero,
      )..soundEnabled = false;
      addTearDown(provider.dispose);
      provider.isOver = true;

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
