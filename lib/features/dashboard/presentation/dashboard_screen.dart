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
                  // 1. 顶部导航
                  _buildTopNavigation(context),
                  const SizedBox(height: 16),
                  // 2. 状态面板
                  _buildStatusPanel(),
                  const SizedBox(height: 16),
                  // 空白区域：将下方组件全部向下挤压
                  const Expanded(child: SizedBox()),
                  // 棋盘（紧凑，不拉伸）
                  const SquareBoard(),
                  const SizedBox(height: 16),
                  // 提词器（紧凑，不抢戏）
                  const TeleprompterView(),
                  const SizedBox(height: 16),
                  // 灵动岛胶囊
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
    return _NavButton(label: label, onTap: onTap);
  }

  /// 构建仿旧版状态卡片组
  Widget _buildStatusPanel() {
    return Consumer<GameProvider>(
      builder: (context, provider, _) {
        return Row(
          children: [
            Expanded(
              child: _buildInfoCard(
                context,
                title: "当前得分 | 连击",
                score: provider.score,
                combo: provider.combo,
                showReset: true,
                onReset: () => _handleReset(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildInfoCard(
                context,
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

  Widget _buildInfoCard(
    BuildContext context, {
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
            crossAxisAlignment: CrossAxisAlignment.center,
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
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildAnimatedCounter(score),
                        const Text(
                          " | ",
                          style: TextStyle(
                            color: Colors.white24,
                            fontSize: 18,
                            fontFamily: 'JetBrains Mono',
                          ),
                        ),
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

class _NavButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;

  const _NavButton({required this.label, this.onTap});

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF22D3EE).withOpacity(0.15),
                const Color(0xFF8B5CF6).withOpacity(0.15),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF22D3EE).withOpacity(0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF22D3EE).withOpacity(0.25),
                blurRadius: 12,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: const Color(0xFF8B5CF6).withOpacity(0.15),
                blurRadius: 8,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}
