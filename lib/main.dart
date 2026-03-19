import 'package:flutter/material.dart';
import 'core/theme/cyber_colors.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';

void main() {
  // 确保 Flutter 引擎在启动前完成所有初始化（为后续多线程/本地数据库预留）
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const YueYouApp());
}

class YueYouApp extends StatelessWidget {
  const YueYouApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
    );
  }
}
