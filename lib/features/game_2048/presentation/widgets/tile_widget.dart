import 'package:flutter/material.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';

/// 单个 2048 数字方块
/// 视觉重构：移除刺眼光效，使用沉稳缩放动画
class TileWidget extends StatefulWidget {
  final int value;

  const TileWidget({super.key, required this.value});

  @override
  State<TileWidget> createState() => _TileWidgetState();
}

class _TileWidgetState extends State<TileWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;
  int _previousValue = 0;

  @override
  void initState() {
    super.initState();
    _previousValue = widget.value;
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );
  }

  @override
  void didUpdateWidget(TileWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 检测合并：值变大且不是空格，触发起泡动画
    if (widget.value != _previousValue &&
        widget.value > _previousValue &&
        widget.value > 0) {
      _scaleController.forward().then((_) => _scaleController.reverse());
    }
    _previousValue = widget.value;
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.value == 0) {
      return const SizedBox.shrink();
    }

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        decoration: BoxDecoration(
          gradient: _getTileGradient(widget.value),
          borderRadius: BorderRadius.circular(14.0),
          boxShadow: _getDynamicGlow(widget.value),
          border: Border.all(
            color: Colors.white.withOpacity(0.05),
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
                color: Colors.black54,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 动态霓虹光晕：根据数字大小生成不同颜色的发光效果
  List<BoxShadow> _getDynamicGlow(int value) {
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
        blurRadius: intensity,
        spreadRadius: 2,
      ),
      BoxShadow(
        color: glowColor.withOpacity(0.3),
        blurRadius: intensity * 1.5,
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
