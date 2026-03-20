import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/database/storage_service.dart';
import 'core/theme/cyber_colors.dart';
import 'features/audio/services/sfx_service.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';
import 'features/game_2048/providers/game_provider.dart';
import 'features/audio/services/tts_engine_service.dart';
import 'features/library/providers/bookshelf_provider.dart';
import 'features/reader/providers/reader_provider.dart';
import 'features/settings/providers/settings_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 启动前初始化持久化层与音效引擎
  await StorageService.init();
  await SfxService.init();
  runApp(const YueYouApp());
}

class YueYouApp extends StatelessWidget {
  const YueYouApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // 1号：全局设置（最先启动，其它 Provider 读取设置值）
        ChangeNotifierProvider(
          create: (_) => SettingsProvider()..loadFromStorage(),
        ),

        // 2号：书架状态
        ChangeNotifierProvider(
          create: (_) => BookshelfProvider()..loadFromStorage(),
        ),

        // 3号：2048 游戏引擎（接入设置里的 soundEnabled）
        ChangeNotifierProxyProvider<SettingsProvider, GameProvider>(
          create: (ctx) {
            final gp = GameProvider();
            gp.soundEnabled = ctx.read<SettingsProvider>().sound;
            return gp;
          },
          update: (ctx, settings, prev) {
            prev?.soundEnabled = settings.sound;
            return prev ?? GameProvider();
          },
        ),

        // 4号：TTS 发声引擎
        ChangeNotifierProvider(create: (_) => TtsEngineService()),

        // 5号：提词器解析引擎（ProxyProvider 注入 TTS 引擎）
        ChangeNotifierProxyProvider<TtsEngineService, ReaderProvider>(
          create: (ctx) => ReaderProvider(ctx.read<TtsEngineService>()),
          update: (ctx, tts, previous) => previous ?? ReaderProvider(tts),
        ),
      ],
      child: MaterialApp(
        title: '阅游 YueYou',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: CyberColors.background,
          colorScheme: const ColorScheme.dark(
            primary: CyberColors.neonGreen,
            secondary: CyberColors.neonPink,
          ),
          useMaterial3: true,
        ),
        home: const DashboardScreen(),
      ),
    );
  }
}
