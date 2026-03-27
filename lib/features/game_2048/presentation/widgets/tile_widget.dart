import 'package:flutter/material.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'merge_particle.dart';

/// 单个 2048 数字方块
/// 合并动画：scale(1.0 → 1.15 → 1.0) + 光晕强化，120ms 完成
class TileWidget extends StatefulWidget {
  final int value;

  const TileWidget({super.key, required this.value});

  @override
  State<TileWidget> createState() => _TileWidgetState();
}

class _TileWidgetState extends State<TileWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _mergeController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;
  int _previousValue = 0;
  bool _showParticles = false;

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
    _mergeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.value == 0) {
      return const SizedBox.shrink();
    }

    return Stack(
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
                  borderRadius: BorderRadius.circular(CyberDimensions.radiusM),
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
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: _getFontSize(widget.value),
                    fontWeight: FontWeight.w900,
                    fontFamily: 'JetBrains Mono',
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
    );
  }

  /// 获取粒子颜色（与光晕颜色一致）
  Color _getParticleColor(int value) {
    if (value <= 16) return const Color(0xFF3B82F6);
    if (value <= 64) return const Color(0xFF8B5CF6);
    if (value <= 256) return const Color(0xFFEC4899);
    if (value <= 1024) return const Color(0xFF22D3EE);
    return const Color(0xFFFFD700);
  }

  /// 动态霓虹光晕：根据数字大小生成不同颜色的发光效果
  /// glowMultiplier: 合并动画时的光晕强度倍数（1.0 ~ 1.8）
  List<BoxShadow> _getDynamicGlow(int value, [double glowMultiplier = 1.0]) {
    Color glowColor;
    double intensity;

    if (value <= 16) {
      // 暗蓝光
      glowColor = const Color(0xFF3B82F6);
      intensity = 8.0;
    } else if (value <= 64) {
      // 紫光
      glowColor = const Color(0xFF8B5CF6);
      intensity = 12.0;
    } else if (value <= 256) {
      // 粉红光
      glowColor = const Color(0xFFEC4899);
      intensity = 16.0;
    } else if (value <= 1024) {
      // 青色赛博光
      glowColor = const Color(0xFF22D3EE);
      intensity = 20.0;
    } else {
      // 金色传说光晕
      glowColor = const Color(0xFFFFD700);
      intensity = 24.0;
    }

    return [
      BoxShadow(
        color: glowColor.withOpacity(0.6),
        blurRadius: intensity * glowMultiplier,
        spreadRadius: 2 * glowMultiplier,
      ),
      BoxShadow(
        color: glowColor.withOpacity(0.3),
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
