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
    final bool isEmpty = widget.value == 0;
    final color = _getTileColor(widget.value);

    return ScaleTransition(
      scale: _scaleAnimation,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: isEmpty ? Colors.white.withOpacity(0.03) : color,
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Center(
          child: Text(
            isEmpty ? "" : widget.value.toString(),
            style: TextStyle(
              color: _getTextColor(widget.value),
              fontSize: _getFontSize(widget.value),
              fontWeight: FontWeight.w900,
              fontFamily: 'JetBrains Mono',
            ),
          ),
        ),
      ),
    );
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

  Color _getTextColor(int val) {
    if (val <= 4) return Colors.white60;
    return Colors.white;
  }

  double _getFontSize(int val) {
    if (val < 100) return 24;
    if (val < 1000) return 20;
    return 16;
  }
}
