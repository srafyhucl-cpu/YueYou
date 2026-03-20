import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:provider/provider.dart';
import '../../game_2048/providers/game_provider.dart';
import '../../game_2048/presentation/widgets/square_board.dart';
import '../../reader/presentation/widgets/teleprompter_view.dart';
import '../../audio/presentation/widgets/cyber_player_console.dart';
import 'package:yueyou/features/library/presentation/screens/library_screen.dart';
import 'package:yueyou/features/reader/presentation/screens/chapter_list_screen.dart';
import 'package:yueyou/features/settings/presentation/screens/settings_screen.dart';
import 'package:yueyou/shared/widgets/cyber_modal.dart';
import 'package:yueyou/shared/widgets/cyber_confirm_dialog.dart';

/// 阅游主仪表盘界面
/// 视觉重塑后的赛博朋克 120 帧高刷渲染面板
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  void _openLibrary(BuildContext context) {
    showCyberModal(
      context: context,
      child: const LibraryScreen(),
    );
  }

  void _openChapterList(BuildContext context) {
    showCyberModal(
      context: context,
      child: const ChapterListScreen(),
    );
  }

  void _openSettings(BuildContext context) {
    showCyberModal(
      context: context,
      child: const SettingsScreen(),
    );
  }

  Future<void> _handleReset(BuildContext context) async {
    final confirmed = await showCyberConfirmDialog(
      context: context,
      title: '重置棋盘',
      message: '确定要重置当前游戏吗？所有进度将会丢失。',
      confirmText: '确认重置',
      cancelText: '取消',
    );
    if (confirmed && context.mounted) {
      context.read<GameProvider>().reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CyberColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  // 1. 顶部 Nav 导航组
                  _buildTopNavigation(context),
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

                  // 5. 底部播放器操作指示 (复刻老项目 CyberPlayer)
                  const CyberPlayerConsole(),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建顶部胶囊按钮组
  Widget _buildTopNavigation(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildNavButton(context, "📚 图书馆", onTap: () => _openLibrary(context)),
        _buildNavButton(context, "📜 目录",
            onTap: () => _openChapterList(context)),
        _buildNavButton(context, "⚙️ 设置", onTap: () => _openSettings(context)),
      ],
    );
  }

  Widget _buildNavButton(BuildContext context, String label,
      {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF22D3EE).withOpacity(0.1),
              const Color(0xFF8B5CF6).withOpacity(0.1),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF22D3EE).withOpacity(0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF22D3EE).withOpacity(0.15),
              blurRadius: 8,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
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
                score: provider.score,
                combo: provider.combo,
                showReset: true,
                onReset: () => _handleReset(context),
              ),
            ),
            const SizedBox(width: 12),
            // 右侧：战绩巅峰
            Expanded(
              child: _buildInfoCard(
                title: "最高得分 | 最高连击",
                score: provider.bestScore,
                combo: provider.maxCombo,
              ),
            ),
          ],
        );
      },
    );
  }

  /// 私有卡片样式生成器 - 注入原生毛玻璃与数字滚动动画
  Widget _buildInfoCard({
    required String title,
    required int score,
    int combo = 0,
    bool showReset = false,
    VoidCallback? onReset,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(16),
          height: 90,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        // 数字滚动动画 - 分数
                        _buildAnimatedCounter(score),
                        const Text(
                          " | ",
                          style: TextStyle(
                            color: Colors.white24,
                            fontSize: 18,
                            fontFamily: 'JetBrains Mono',
                          ),
                        ),
                        // 数字滚动动画 - 连击
                        _buildAnimatedCounter(combo, isCombo: true),
                      ],
                    ),
                  ),
                  if (showReset)
                    GestureDetector(
                      onTap: onReset,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.refresh,
                            color: Colors.white, size: 18),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 核心数字滚动组件
  Widget _buildAnimatedCounter(int value, {bool isCombo = false}) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, child) {
        return Text(
          "$animatedValue",
          style: TextStyle(
            color: isCombo ? CyberColors.neonPink : Colors.white,
            fontSize: 20,
            fontFamily: 'JetBrains Mono',
            fontWeight: FontWeight.bold,
            shadows: [
              if (isCombo)
                Shadow(
                  color: CyberColors.pinkGlow.withOpacity(0.5),
                  blurRadius: 8,
                )
              else
                Shadow(
                  color: Colors.white.withOpacity(0.3),
                  blurRadius: 4,
                ),
            ],
          ),
        );
      },
    );
  }
}
