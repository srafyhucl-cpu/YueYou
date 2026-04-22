import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import '../../game_2048/providers/game_provider.dart';
import '../../game_2048/presentation/widgets/square_board.dart';
import '../../game_2048/presentation/widgets/board_mascot.dart';
import '../../reader/presentation/widgets/teleprompter_view.dart';
import '../../audio/presentation/widgets/cyber_player_console.dart';
import 'package:yueyou/features/library/presentation/screens/library_screen.dart';
import 'package:yueyou/features/reader/presentation/screens/chapter_list_screen.dart';
import 'package:yueyou/features/settings/presentation/screens/settings_screen.dart';
import 'package:yueyou/shared/widgets/cyber_modal.dart';
import 'package:yueyou/shared/widgets/cyber_confirm_dialog.dart';

/// 阅游主仪表盘界面
/// 视觉重塑后的赛博朋克 120 帧高刷渲染面板
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  /// GlobalKey 持有在 State 层，避免每次 build 重新创建导致组件卸载
  final GlobalKey<BoardMascotState> _mascotKey = GlobalKey<BoardMascotState>();

  @override
  void initState() {
    super.initState();
    // Task 4: 版本更新检测（首帧渲染完毕后执行，不阻塞 UI）
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAppUpdates());
  }

  /// 版本更新检测桩（Update Checker Stub）
  ///
  /// TODO: V1.1 实现远端版本比对逻辑：
  ///   1. GET https://api.yueyou.app/version 获取 JSON {"version": "x.y.z", "forceUpdate": false}
  ///   2. 与 PackageInfo.fromPlatform().version 比对
  ///   3. 若有新版本，调用 showCyberConfirmDialog(context, title: '发现新版本', ...) 提示用户
  ///   4. forceUpdate == true 时禁用取消按钮，强制跳转应用市场
  Future<void> _checkAppUpdates() async {
    // TODO: V1.1 接入远端版本检测接口
  }

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
                      CyberColors.neonCyan.withValues(alpha: 0.03),
                      CyberColors.background,
                      CyberColors.neonPurple.withValues(alpha: 0.02),
                    ],
                  ),
                ),
              ),
            ),
            // 主内容
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: CyberDimensions.spacingM),
              child: Column(
                children: [
                  const SizedBox(height: CyberDimensions.spacingM),
                  // 1. 顶部导航
                  _buildTopNavigation(context),
                  const SizedBox(height: CyberDimensions.spacingM),
                  // 2. 状态面板
                  _buildStatusPanel(),
                  // 棋盘 + XIAOYO 爬墙头
                  // 76px 缓冲区合并进 Expanded 内部计算，保证 mascotTop 始终为正值（在 Stack 边界内）
                  Expanded(
                    flex: 2,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const double kBuffer =
                            CyberDimensions.dashboardBoardBuffer;
                        final w = constraints.maxWidth;
                        final h = constraints.maxHeight;
                        // 棋盘可用高度 = 总高 - 顶部缓冲区
                        final boardAvailH = h - kBuffer;
                        final boardSz = w < boardAvailH ? w : boardAvailH;
                        // 棋盘顶部位置 = 缓冲区 + 剩余居中空间
                        final boardTop = kBuffer + (boardAvailH - boardSz) / 2;
                        // XIAOYO 顶部 = boardTop - 73，由于 boardTop >= kBuffer = 76 > 73，始终为正数
                        final mascotTop = boardTop -
                            (CyberDimensions.dashboardMascotHeight -
                                CyberDimensions.spacingMS +
                                1);

                        return Stack(
                          children: [
                            // 1. 棋盘层（在缓冲区下方居中）
                            Positioned(
                              top: boardTop,
                              left: 0,
                              right: 0,
                              height: boardSz,
                              child: const SquareBoard(),
                            ),

                            // 2. XIAOYO 渲染层（纯渲染，不处理手势）
                            Positioned(
                              top: mascotTop,
                              left: (w - CyberDimensions.dashboardMascotWidth) /
                                  2,
                              width: CyberDimensions.dashboardMascotWidth,
                              height: CyberDimensions.dashboardMascotHeight,
                              child: IgnorePointer(
                                child: BoardMascot(key: _mascotKey),
                              ),
                            ),

                            // 3. XIAOYO 点击层（透明覆盖，独立于棋盘手势）
                            Positioned(
                              top: mascotTop,
                              left: (w - CyberDimensions.dashboardMascotWidth) /
                                  2,
                              width: CyberDimensions.dashboardMascotWidth,
                              height: CyberDimensions.dashboardMascotHeight,
                              child: GestureDetector(
                                onTap: () {
                                  debugPrint('🎯 XIAOYO 点击层被触发');
                                  _mascotKey.currentState
                                      ?.triggerTapAnimation();
                                },
                                behavior: HitTestBehavior.opaque,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: CyberDimensions.spacingM),
                  // 提词器（带边框容器）
                  const RepaintBoundary(child: TeleprompterView()),
                  const SizedBox(height: CyberDimensions.borderNormal),
                  // 灵动岛胶囊（内部有 Padding(top:15)，总视觉间距 = 1 + 15 = 16px）
                  const CyberPlayerConsole(),
                  const SizedBox(height: CyberDimensions.spacingM),
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
            const SizedBox(width: CyberDimensions.spacingMS),
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
          padding: const EdgeInsets.symmetric(
            horizontal: CyberDimensions.spacingMS + CyberDimensions.spacingXXS,
            vertical: CyberDimensions.spacingS + CyberDimensions.spacingXXS,
          ),
          constraints: const BoxConstraints(
              minHeight: CyberDimensions.dashboardStatusCardMinHeight),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                CyberColors.whiteFaint,
                CyberColors.whiteFaint.withValues(alpha: 0.03),
              ],
            ),
            borderRadius: BorderRadius.circular(CyberDimensions.radiusL),
            border: Border.all(
              color: CyberColors.neonCyan.withValues(alpha: 0.2),
              width: CyberDimensions.borderThick,
            ),
            boxShadow: [
              BoxShadow(
                color: CyberColors.neonCyan.withValues(alpha: 0.1),
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
                style: CyberTextStyles.overlineTiny.copyWith(
                  color: CyberColors.neonCyan.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(
                  height:
                      CyberDimensions.spacingS - CyberDimensions.spacingXXS),
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
                            style: CyberTextStyles.dashboardSeparator,
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
                        size: CyberDimensions.iconM,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: CyberColors.neonCyan.withValues(alpha: 0.15),
                        padding: const EdgeInsets.all(CyberDimensions.spacingS),
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
          style: CyberTextStyles.dashboardCounter.copyWith(
            color: isCombo ? CyberColors.neonPink : CyberColors.neonCyan,
            shadows: [
              if (isCombo)
                Shadow(
                  color: CyberColors.pinkGlow.withValues(alpha: 0.6),
                  blurRadius: 12,
                )
              else
                Shadow(
                  color: CyberColors.neonCyan.withValues(alpha: 0.5),
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
        padding:
            const EdgeInsets.symmetric(vertical: CyberDimensions.spacingMS),
        decoration: BoxDecoration(
          color: _isPressed
              ? CyberColors.neonCyan.withValues(alpha: 0.12)
              : CyberColors.transparent,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.item.icon,
              color: CyberColors.neonCyan.withValues(alpha: 0.8),
              size: CyberDimensions.iconS,
            ),
            const SizedBox(
                width: CyberDimensions.spacingS - CyberDimensions.spacingXXS),
            Text(
              widget.item.label,
              style: CyberTextStyles.segmentLabel,
            ),
          ],
        ),
      ),
    );
  }
}
