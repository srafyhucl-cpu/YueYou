import 'dart:async';
import 'package:flutter/material.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'merge_particle.dart';

/// 单个 2048 数字方块
/// 合并动画：scale(1.0 → 1.15 → 1.0) + 光晕强化，120ms 完成
/// 黑客后门彩蛋：连续点击 8 次触发崩塌消除动画
class TileWidget extends StatefulWidget {
  final int value;
  final int? id;
  final VoidCallback? onEliminate;

  const TileWidget({
    super.key,
    required this.value,
    this.id,
    this.onEliminate,
  });

  @override
  State<TileWidget> createState() => _TileWidgetState();
}

class _TileWidgetState extends State<TileWidget> with TickerProviderStateMixin {
  late AnimationController _mergeController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;
  late AnimationController _eliminateController;
  late Animation<double> _eliminateScaleAnimation;
  late Animation<double> _eliminateOpacityAnimation;
  late Animation<double> _eliminateRotationAnimation;
  Timer? _tapResetTimer;
  int _previousValue = 0;
  bool _showParticles = false;
  int _tapCount = 0;
  bool _isEliminating = false;

  @override
  void initState() {
    super.initState();
    _previousValue = widget.value;
    _mergeController = AnimationController(
      duration: const Duration(milliseconds: 120),
      vsync: this,
    );

    // 弹性缩放曲线：1.0 → 1.15 → 1.0
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.15)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.15, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(_mergeController);

    // 光晕强化：1.0 → 1.8 → 1.0
    _glowAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.8),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.8, end: 1.0),
        weight: 50,
      ),
    ]).animate(_mergeController);

    // 崩塌消除动画：450ms，三段式视觉冲击
    _eliminateController = AnimationController(
      duration: const Duration(milliseconds: 450),
      vsync: this,
    );
    // 先膨胀 (0→25%) 再坍缩至 0 (25→100%)，easeInBack 产生回弹感
    _eliminateScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.3)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.3, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInBack)),
        weight: 75,
      ),
    ]).animate(_eliminateController);
    // 前 60% 保持不透明，后 40% 快速消散
    _eliminateOpacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0),
        weight: 40,
      ),
    ]).animate(_eliminateController);
    // 坍缩时微微旋转，强化「被删除」的混乱感
    _eliminateRotationAnimation = Tween<double>(begin: 0.0, end: 0.25)
        .chain(CurveTween(curve: Curves.easeIn))
        .animate(_eliminateController);
  }

  @override
  void didUpdateWidget(TileWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 检测到值变化（合并发生）→ 触发动画 + 粒子效果
    if (widget.value != _previousValue && widget.value > _previousValue) {
      _previousValue = widget.value;
      _mergeController.forward(from: 0.0);
      setState(() => _showParticles = true);
    }
  }

  @override
  void dispose() {
    _tapResetTimer?.cancel();
    _mergeController.dispose();
    _eliminateController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (_isEliminating) return;
    _tapResetTimer?.cancel();
    _tapCount++;
    if (_tapCount < 8) {
      _mergeController.forward(from: 0.3);
      // 1.5s 内无后续点击则视为中断，计数清零
      _tapResetTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _tapCount = 0);
      });
    } else {
      setState(() {
        _isEliminating = true;
        _showParticles = true;
      });
      _eliminateController.forward().then((_) {
        widget.onEliminate?.call();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.value == 0) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _eliminateController,
        builder: (context, child) {
          return Transform.scale(
            scale: _eliminateScaleAnimation.value,
            child: Transform.rotate(
              angle: _eliminateRotationAnimation.value,
              child: Opacity(
                opacity: _eliminateOpacityAnimation.value,
                child: child,
              ),
            ),
          );
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 主方块
            AnimatedBuilder(
              animation: _mergeController,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: _getTileGradient(widget.value),
                      borderRadius:
                          BorderRadius.circular(CyberDimensions.radiusM),
                      boxShadow:
                          _getDynamicGlow(widget.value, _glowAnimation.value),
                      border: Border.all(
                        color: CyberColors.whiteFaint,
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${widget.value}',
                      style: CyberTextStyles.gameGridNumber.copyWith(
                        color: CyberColors.whiteHigh,
                        fontSize: _getFontSize(widget.value),
                        fontFamily: CyberTextStyles.monoFont,
                        shadows: const [
                          Shadow(
                            color: CyberColors.blackDim,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            // 粒子效果层
            if (_showParticles)
              Positioned.fill(
                child: MergeParticle(
                  color: _getParticleColor(widget.value),
                  onComplete: () {
                    if (mounted) {
                      setState(() => _showParticles = false);
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 获取粒子颜色（与光晕颜色一致）
  /// 黑客消除时强制返回危险警告色
  Color _getParticleColor(int value) {
    if (_isEliminating) return CyberColors.neonPink;
    if (value <= 16) return CyberColors.tileBlue;
    if (value <= 64) return CyberColors.neonPurple;
    if (value <= 256) return CyberColors.hotPink;
    if (value <= 1024) return CyberColors.neonCyan;
    return CyberColors.tileGold;
  }

  /// 动态霓虹光晕：根据数字大小生成不同颜色的发光效果
  /// glowMultiplier: 合并动画时的光晕强度倍数（1.0 ~ 1.8）
  List<BoxShadow> _getDynamicGlow(int value, [double glowMultiplier = 1.0]) {
    Color glowColor;
    double intensity;

    if (value <= 16) {
      // 暗蓝光
      glowColor = CyberColors.tileBlue;
      intensity = 8.0;
    } else if (value <= 64) {
      // 紫光
      glowColor = CyberColors.neonPurple;
      intensity = 12.0;
    } else if (value <= 256) {
      // 粉红光
      glowColor = CyberColors.hotPink;
      intensity = 16.0;
    } else if (value <= 1024) {
      // 青色赛博光
      glowColor = CyberColors.neonCyan;
      intensity = 20.0;
    } else {
      // 金色传说光晕
      glowColor = CyberColors.tileGold;
      intensity = 24.0;
    }

    return [
      BoxShadow(
        color: glowColor.withValues(alpha: 0.6),
        blurRadius: intensity * glowMultiplier,
        spreadRadius: 2 * glowMultiplier,
      ),
      BoxShadow(
        color: glowColor.withValues(alpha: 0.3),
        blurRadius: intensity * 1.5 * glowMultiplier,
        spreadRadius: 0,
      ),
    ];
  }

  /// 提取自旧版style.css的经典渐变配色
  LinearGradient _getTileGradient(int val) {
    return switch (val) {
      2 => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CyberColors.tile2Start, CyberColors.tile2End],
        ),
      4 => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CyberColors.tile4Start, CyberColors.tile4End],
        ),
      8 => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CyberColors.tile8Start, CyberColors.tile8End],
        ),
      16 => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CyberColors.tile16Start, CyberColors.tile16End],
        ),
      32 => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CyberColors.tile32Start, CyberColors.tile32End],
        ),
      64 => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CyberColors.tile64Start, CyberColors.tile64End],
        ),
      128 => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CyberColors.tile128Start, CyberColors.tile128End],
        ),
      256 => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CyberColors.tile256Start, CyberColors.tile256End],
        ),
      512 => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CyberColors.tile512Start, CyberColors.tile512End],
        ),
      1024 => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CyberColors.tile1024Start, CyberColors.tile1024End],
        ),
      2048 => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CyberColors.tile2048Start, CyberColors.tile2048End],
        ),
      _ => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CyberColors.neonPink, CyberColors.neonPurple],
        ),
    };
  }

  double _getFontSize(int val) {
    if (val < 100) return 24;
    if (val < 1000) return 20;
    return 16;
  }
}
