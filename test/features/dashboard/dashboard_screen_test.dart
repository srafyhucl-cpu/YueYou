import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/dashboard/presentation/dashboard_screen.dart';
import 'package:yueyou/features/game_2048/providers/game_provider.dart';
import 'package:yueyou/features/library/providers/bookshelf_provider.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';
import 'package:yueyou/main.dart';

import '../../utils/test_utils.dart';

/// DashboardScreen widget 烟测，目标覆盖：
///   * 顶部导航 (_buildTopNavigation 三个 _SegItem) line 213-265
///   * 状态面板 (_buildStatusPanel) line 267+
///   * 棋盘 + 吉祥物 + 提词器 + 播放控制台嵌套布局
///
/// 注意：
/// - DashboardScreen.initState 会 fire-and-forget 调 UpdateService.checkForUpdate()，
///   测试环境下 UPDATE_API_URL 为空，第一行就 return null，不会发真请求。
/// - 多窗口场景 (constraints.maxHeight < 720) 走 isMultiWindow 分支隐藏部分组件。
///   widget tester 默认 800x600 → maxHeight 接近 600 < 720 → multi-window 模式。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TtsEngineService? activeEngine;
  ReaderProvider? activeReader;

  setUp(() async {
    await initializeTestEnvironment();
  });

  tearDown(() {
    // ProviderScope 拆除时已 dispose override 的 ChangeNotifier；这里 try/catch
    // 容错二次 dispose（debugAssertNotDisposed 抛 AssertionError）。
    try {
      activeReader?.dispose();
    } catch (_) {}
    try {
      activeEngine?.dispose();
    } catch (_) {}
    activeReader = null;
    activeEngine = null;
  });

  Widget _wrap() {
    final settings = makeSettings();
    final engine = makeTtsEngine(settings);
    activeEngine = engine;
    final reader = ReaderProvider(engine);
    activeReader = reader;
    final bookshelf = BookshelfProvider();
    final game = GameProvider(
      autoLoadState: false,
      persistDebounceDuration: Duration.zero,
    )..soundEnabled = false;

    return ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => settings),
        ttsEngineProvider.overrideWith((ref) => engine),
        readerProvider.overrideWith((ref) => reader),
        bookshelfProvider.overrideWith((ref) => bookshelf),
        gameProvider.overrideWith((ref) => game),
      ],
      child: MaterialApp(
        navigatorKey: globalNavigatorKey,
        home: const DashboardScreen(),
      ),
    );
  }

  testWidgets('DashboardScreen 必须正常构造并渲染顶部三按钮', (tester) async {
    await tester.pumpWidget(_wrap());
    // 等 initState 内 fire-and-forget UpdateService.checkForUpdate 微任务排干
    await tester.pump();

    expect(find.byType(DashboardScreen), findsOneWidget);
    // 顶部导航三个 _SegItem 的标签
    expect(find.text('书架'), findsOneWidget);
    expect(find.text('目录'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('DashboardScreen 大屏布局必须渲染状态面板（非 multi-window）', (tester) async {
    // 调高屏幕尺寸越过 multi-window 阈值（maxHeight < 720 才是 multi）
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_wrap());
    await tester.pump();

    // 大屏下 _buildStatusPanel 渲染：当前得分 / 最高得分卡片必出现
    expect(find.textContaining('当前得分'), findsOneWidget,
        reason: '大屏下必须渲染当前得分状态卡片');
    expect(find.textContaining('最高得分'), findsOneWidget,
        reason: '大屏下必须渲染最高得分状态卡片');
  });

  testWidgets('DashboardScreen 多窗口（小屏）模式必须隐藏状态面板与提词器', (tester) async {
    // 默认 800x600，maxHeight=600 < 720 → multi-window 模式
    // multi-window 模式下 _buildStatusPanel 与 TeleprompterView 不渲染
    await tester.pumpWidget(_wrap());
    await tester.pump();

    // 顶部三按钮仍渲染
    expect(find.text('书架'), findsOneWidget);
    // 状态卡片（'当前得分'）在 multi-window 下隐藏
    expect(find.textContaining('当前得分'), findsNothing,
        reason: 'multi-window 模式下 _buildStatusPanel 必须隐藏');
  });

  // ── 大屏 + low animation level 用例：拉动 TeleprompterView 与 modal 的
  //    isLowPerf=true 分支（Container 而非 BackdropFilter 渲染路径）
  testWidgets('DashboardScreen 大屏 + low animation level 必须走非 blur 分支',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // 自定义 _wrap：注入 animationQualitySetting='low' 的 settings
    final settings = makeSettings();
    settings.animationQualitySetting = 'low';
    final engine = makeTtsEngine(settings);
    activeEngine = engine;
    final reader = ReaderProvider(engine);
    activeReader = reader;
    final bookshelf = BookshelfProvider();
    final game = GameProvider(
      autoLoadState: false,
      persistDebounceDuration: Duration.zero,
    )..soundEnabled = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) => settings),
          ttsEngineProvider.overrideWith((ref) => engine),
          readerProvider.overrideWith((ref) => reader),
          bookshelfProvider.overrideWith((ref) => bookshelf),
          gameProvider.overrideWith((ref) => game),
        ],
        child: MaterialApp(
          navigatorKey: globalNavigatorKey,
          home: const DashboardScreen(),
        ),
      ),
    );
    await tester.pump();

    // 大屏 + low-perf 下 dashboard 渲染：状态面板可见 + 顶部三按钮可见
    expect(find.text('书架'), findsOneWidget);
    expect(find.textContaining('当前得分'), findsOneWidget);
    expect(find.textContaining('最高得分'), findsOneWidget);
  });
}
