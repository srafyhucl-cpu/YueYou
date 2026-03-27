import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CyberColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // 背景渐变效果
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 1.5,
                    colors: [
                      CyberColors.neonCyan.withOpacity(0.03),
                      CyberColors.background,
                      CyberColors.neonPurple.withOpacity(0.02),
                    ],
                  ),
                ),
              ),
            ),
            // 主内容
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  // 1. 顶部导航
                  _buildTopNavigation(context),
                  const SizedBox(height: 12),
                  // 2. 状态面板
                  _buildStatusPanel(),
                  const SizedBox(height: 16),
                  // 棋盘（垂直居中偏上，人体工学优化）
                  const Expanded(
                    flex: 2,
                    child: Center(
                      child: SquareBoard(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 提词器（紧凑，不抢戏）
                  const TeleprompterView(),
                  const SizedBox(height: 12),
                  // 灵动岛胶囊
                  const CyberPlayerConsole(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建顶部玻璃工具栏（全宽毛玻璃条，三个 icon+文字 等分排列，与灵动岛视觉统一）
  Widget _buildTopNavigation(BuildContext context) {
    final items = [
      _SegItem(
          icon: Icons.menu_book_rounded,
          label: '书架',
          onTap: () => _openLibrary(context)),
      _SegItem(
          icon: Icons.list_rounded,
          label: '目录',
          onTap: () => _openChapterList(context)),
      _SegItem(
          icon: Icons.tune_rounded,
          label: '设置',
          onTap: () => _openSettings(context)),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(CyberDimensions.radiusL),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: CyberDimensions.blurMedium,
          sigmaY: CyberDimensions.blurMedium,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: CyberColors.glassDark,
            borderRadius: BorderRadius.circular(CyberDimensions.radiusL),
            border: Border.all(
              color: CyberColors.whiteBorder,
              width: CyberDimensions.borderNormal,
            ),
          ),
          child: Row(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                if (i > 0)
                  Container(
                    width: 1,
                    height: 22,
                    color: CyberColors.whiteFaint,
                  ),
                Expanded(child: _SegButton(item: items[i])),
              ],
            ],
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
            Expanded(
              child: _buildInfoCard(
                context,
                title: "当前得分 | 连击",
                score: provider.score,
                combo: provider.combo,
                showReset: true, // 🔥 找回重置按钮
                onReset: () async {
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
                },
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
      borderRadius: BorderRadius.circular(CyberDimensions.radiusL),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: CyberDimensions.blurStrong,
          sigmaY: CyberDimensions.blurStrong,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: const BoxConstraints(minHeight: 85),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                CyberColors.whiteFaint,
                CyberColors.whiteFaint.withOpacity(0.03),
              ],
            ),
            borderRadius: BorderRadius.circular(CyberDimensions.radiusL),
            border: Border.all(
              color: CyberColors.neonCyan.withOpacity(0.2),
              width: CyberDimensions.borderThick,
            ),
            boxShadow: [
              BoxShadow(
                color: CyberColors.neonCyan.withOpacity(0.1),
                blurRadius: 12,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: CyberColors.neonCyan.withOpacity(0.6),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildAnimatedCounter(score),
                          const Text(
                            " | ",
                            style: TextStyle(
                              color: CyberColors.whiteSubtle,
                              fontSize: 16,
                              fontFamily: 'JetBrains Mono',
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                          _buildAnimatedCounter(combo, isCombo: true),
                        ],
                      ),
                    ),
                  ),
                  if (showReset)
                    IconButton(
                      onPressed: onReset,
                      icon: const Icon(
                        Icons.refresh,
                        color: CyberColors.neonCyan,
                        size: 20,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: CyberColors.neonCyan.withOpacity(0.15),
                        padding: const EdgeInsets.all(8),
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
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, child) {
        return Text(
          "$animatedValue",
          style: TextStyle(
            color: isCombo ? CyberColors.neonPink : CyberColors.neonCyan,
            fontSize: 22,
            fontFamily: 'JetBrains Mono',
            fontWeight: FontWeight.w900,
            shadows: [
              if (isCombo)
                Shadow(
                  color: CyberColors.pinkGlow.withOpacity(0.6),
                  blurRadius: 12,
                )
              else
                Shadow(
                  color: CyberColors.neonCyan.withOpacity(0.5),
                  blurRadius: 8,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SegItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SegItem(
      {required this.icon, required this.label, required this.onTap});
}

class _SegButton extends StatefulWidget {
  final _SegItem item;
  const _SegButton({required this.item});

  @override
  State<_SegButton> createState() => _SegButtonState();
}

class _SegButtonState extends State<_SegButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.item.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: _isPressed
              ? CyberColors.neonCyan.withOpacity(0.12)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.item.icon,
              color: CyberColors.neonCyan.withOpacity(0.8),
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              widget.item.label,
              style: const TextStyle(
                color: CyberColors.whiteHigh,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
