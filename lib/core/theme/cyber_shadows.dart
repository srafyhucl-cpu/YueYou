import 'package:flutter/material.dart';
import 'cyber_colors.dart';

/// 赛博朋克设计系统 - 阴影规范
/// 统一管理阴影效果，确保视觉层次一致
class CyberShadows {
  // ==================== 标准阴影系统 ====================
  
  /// 悬浮阴影 - 用于大型容器（棋盘、卡片）
  /// 强烈的悬浮感，适合主要内容区域
  static const List<BoxShadow> elevated = [
    BoxShadow(
      color: CyberColors.blackShadow,
      blurRadius: 30,
      offset: Offset(0, 10),
    ),
  ];
  
  /// 浮动阴影 - 用于中型组件（书架卡片、导入按钮）
  /// 轻微悬浮感，适合次要内容
  static const List<BoxShadow> floating = [
    BoxShadow(
      color: CyberColors.blackShadow,
      blurRadius: 16,
      offset: Offset(0, 6),
    ),
  ];
  
  /// 贴近阴影 - 用于小型组件（播放按钮、小卡片）
  /// 贴近表面，适合细节装饰
  static const List<BoxShadow> subtle = [
    BoxShadow(
      color: CyberColors.blackShadow,
      blurRadius: 10,
      offset: Offset(0, 4),
    ),
  ];

  // ==================== 霓虹光晕阴影 ====================
  
  /// 创建霓虹光晕效果
  /// 用于方块、按钮等需要发光效果的元素
  static List<BoxShadow> neonGlow({
    required Color color,
    double intensity = 1.0,
  }) {
    return [
      BoxShadow(
        color: color.withValues(alpha: 0.6 * intensity),
        blurRadius: 12 * intensity,
        spreadRadius: 2 * intensity,
      ),
      BoxShadow(
        color: color.withValues(alpha: 0.3 * intensity),
        blurRadius: 18 * intensity,
        spreadRadius: 0,
      ),
    ];
  }
}
