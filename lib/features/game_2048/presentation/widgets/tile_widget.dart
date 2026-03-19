import 'package:flutter/material.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';

/// 单个 2048 数字方块
/// 视觉重构：1:1 复刻旧版图示中的霓虹质感与配色方案
class TileWidget extends StatelessWidget {
  final int value;

  const TileWidget({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    final bool isEmpty = value == 0;
    final color = _getTileColor(value);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: isEmpty ? Colors.white.withOpacity(0.03) : color,
        borderRadius: BorderRadius.circular(16.0), // 提升圆角质感
        boxShadow: value >= 8 
            ? [
                BoxShadow(
                  color: color.withOpacity(0.4),
                  blurRadius: 15.0,
                  spreadRadius: 1.0,
                )
              ] 
            : null,
      ),
      child: Center(
        child: Text(
          isEmpty ? "" : value.toString(),
          style: TextStyle(
            color: _getTextColor(value),
            fontSize: _getFontSize(value),
            fontWeight: FontWeight.w900,
            fontFamily: 'JetBrains Mono',
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
