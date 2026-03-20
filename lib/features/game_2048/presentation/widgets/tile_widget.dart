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
          color: _getTileColor(widget.value),
          borderRadius: BorderRadius.circular(16.0),
          boxShadow: _getDynamicGlow(widget.value),
        ),
        alignment: Alignment.center,
        child: Text(
          '${widget.value}',
          style: TextStyle(
            color: widget.value <= 4 ? Colors.black87 : Colors.white,
            fontSize: _getFontSize(widget.value),
            fontWeight: FontWeight.w900,
            fontFamily: 'JetBrains Mono',
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

  /// 依据图一配置的赛博色彩映射表
  Color _getTileColor(int val) {
    return switch (val) {
      2 => CyberColors.tile2,
      4 => CyberColors.tile4,
      8 => CyberColors.tile8,
      16 => CyberColors.tile16,
      32 => CyberColors.tile32,
      64 => CyberColors.tile64,
      128 => CyberColors.tile128,
      256 => CyberColors.tile256,
      512 => CyberColors.tile512,
      _ => CyberColors.neonPink,
    };
  }

  double _getFontSize(int val) {
    if (val < 100) return 24;
    if (val < 1000) return 20;
    return 16;
  }
}
