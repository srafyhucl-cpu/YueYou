import 'package:flutter/material.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:provider/provider.dart';
import '../../game_2048/providers/game_provider.dart';
import '../../reader/presentation/widgets/teleprompter_view.dart';
import '../../game_2048/presentation/widgets/square_board.dart';

/// 阅游主仪表盘界面
/// 视觉重塑后的赛博朋克 120 帧高刷渲染面板
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 注入全局 Provider 状态管理，用于计分板实时刷新
    return ChangeNotifierProvider(
      create: (_) => GameProvider(),
      child: Scaffold(
        backgroundColor: CyberColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: [
                const SizedBox(height: 16),
                // 1. 顶部 Nav 导航组 (虽然目前是静态，但保持骨架到位)
                _buildTopNavigation(),
                const SizedBox(height: 24),

                // 2. 核心状态面板 (双子卡片式设计 - 实时分数)
                _buildStatusPanel(),
                const SizedBox(height: 24),

                // 3. 2048 核心战斗机舱 (1:1 响应式正方形网格)
                const Expanded(
                  flex: 3,
                  child: Center(
                    child: SquareBoard(),
                  ),
                ),

                // 4. 底部动态小说提词区 (文字流式渲染)
                const Expanded(
                  flex: 1,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 24.0),
                    child: TeleprompterView(),
                  ),
                ),
                
                // 5. 底部播放器操作指示 (预留)
                _buildBottomControlBar(),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建顶部胶囊按钮组
  Widget _buildTopNavigation() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildNavButton("📚 图书馆", Icons.library_books),
        _buildNavButton("📜 目录", Icons.list),
        _buildNavButton("🌌 星图", Icons.auto_awesome),
        _buildNavButton("⚙️ 设置", Icons.settings),
      ],
    );
  }

  Widget _buildNavButton(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: CyberColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  /// 构建仿旧版状态卡片组
  Widget _buildStatusPanel() {
    return Consumer<GameProvider>(
      builder: (context, provider, _) {
        return Row(
          children: [
            // 左侧：实时分与连击情况
            Expanded(
              child: _buildInfoCard(
                title: "当前得分 | 连击",
                value: "${provider.score} | ${provider.combo}",
                showReset: true,
                onReset: () => provider.reset(),
              ),
            ),
            const SizedBox(width: 12),
            // 右侧：战绩巅峰
            Expanded(
              child: _buildInfoCard(
                title: "最高得分 | 最高连击",
                value: "${provider.bestScore} | ${provider.maxCombo}",
              ),
            ),
          ],
        );
      },
    );
  }

  /// 私有卡片样式生成器
  Widget _buildInfoCard({
    required String title,
    required String value,
    bool showReset = false,
    VoidCallback? onReset,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      height: 90,
      decoration: BoxDecoration(
        color: CyberColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontFamily: 'JetBrains Mono',
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (showReset)
                GestureDetector(
                  onTap: onReset,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Colors.white12,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.refresh, color: Colors.white, size: 18),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControlBar() {
     return Container(
       height: 60,
       width: double.infinity,
       padding: const EdgeInsets.symmetric(horizontal: 20),
       decoration: BoxDecoration(
         color: CyberColors.cardBackground,
         borderRadius: BorderRadius.circular(30),
         border: Border.all(color: CyberColors.neonPink.withOpacity(0.3)),
         boxShadow: [
           BoxShadow(color: CyberColors.pinkGlow.withOpacity(0.1), blurRadius: 15)
         ]
       ),
       child: Row(
         children: [
           const Icon(Icons.bar_chart, color: CyberColors.neonPink, size: 24),
           const SizedBox(width: 16),
           const Icon(Icons.pause, color: Colors.white, size: 28),
           const SizedBox(width: 16),
           const Expanded(
             child: Text(
               "神经数据流已同步...",
               style: TextStyle(color: Colors.white54, fontSize: 12),
             ),
           ),
           const Text("1.0x", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
         ],
       ),
     );
  }
}
