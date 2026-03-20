import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/cyber_colors.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';
import 'features/game_2048/providers/game_provider.dart';
import 'features/audio/services/tts_engine_service.dart';
import 'features/reader/providers/reader_provider.dart';

void main() {
  // 确保 Flutter 引擎在启动前完成所有初始化（为后续多线程/本地数据库预留）
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const YueYouApp());
}

class YueYouApp extends StatelessWidget {
  const YueYouApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // 1号插头：2048 游戏引擎
        ChangeNotifierProvider(create: (_) => GameProvider()),

        // 2号插头：TTS 发声引擎（必须放在 Reader 前面）
        ChangeNotifierProvider(create: (_) => TtsEngineService()),

        // 3号插头：提词器解析引擎（使用 ProxyProvider 将 TTS 引擎注入进去！）
        ChangeNotifierProxyProvider<TtsEngineService, ReaderProvider>(
          create: (context) => ReaderProvider(context.read<TtsEngineService>()),
          update: (context, tts, previous) => previous ?? ReaderProvider(tts),
        ),
      ],
      child: MaterialApp(
        title: '阅游 YueYou',
        // 摘掉右上角的 Debug 标签，保持沉浸感
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          // 全局强制使用赛博朋克深色背景
          scaffoldBackgroundColor: CyberColors.background,
          colorScheme: const ColorScheme.dark(
            primary: CyberColors.neonGreen,
            secondary: CyberColors.neonPink,
          ),
          useMaterial3: true,
        ),
        // 直接将路由指向刚刚写好的主控台
        home: const DashboardScreen(),
      ),
    );
  }
}
