import 'package:flutter/material.dart';
import 'cyber_colors.dart';

class CyberTextStyles {
  static const String monoFont = 'JetBrains Mono';
  // 提词器正在阅读的【高亮发光文字】
  static const TextStyle teleprompterActive = TextStyle(
    color: CyberColors.neonGreen,
    fontSize: 24,
    fontWeight: FontWeight.bold,
    letterSpacing: 2.0, // 字间距拉开，更有极客敲代码的呼吸感
    shadows: [
      Shadow(
        blurRadius: 10.0, // 发光半径
        color: CyberColors.glowShadow,
        offset: Offset(0, 0),
      ),
    ],
  );

  // 提词器下方还没读到的【暗色背景文字】
  static const TextStyle teleprompterDim = TextStyle(
    color: CyberColors.textDim,
    fontSize: 24,
    fontWeight: FontWeight.normal,
    letterSpacing: 2.0,
  );

  // 2048 棋盘上的数字字体
  static const TextStyle gameGridNumber = TextStyle(
    color: CyberColors.background,
    fontSize: 28,
    fontWeight: FontWeight.w900,
  );

  // ==================== 通用 UI 文本样式 ====================

  /// 页面头部标题（18px, bold, letterSpacing: 2）
  /// 使用时通过 copyWith(color: ...) 设置具体颜色
  static const TextStyle screenTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    letterSpacing: 2,
  );

  /// 分区标题（12px, bold, letterSpacing: 1.5, neonGreen）
  static const TextStyle sectionLabel = TextStyle(
    color: CyberColors.neonGreen,
    fontSize: 12,
    fontWeight: FontWeight.bold,
    letterSpacing: 1.5,
  );

  /// 列表项主标题（14px, whiteHigh）
  static const TextStyle tileTitle = TextStyle(
    color: CyberColors.whiteHigh,
    fontSize: 14,
  );

  /// 列表项副标题（12px, whiteMuted）
  static const TextStyle tileSubtitle = TextStyle(
    color: CyberColors.whiteMuted,
    fontSize: 12,
  );

  /// 标签文字（14px, whiteDim）
  static const TextStyle labelMedium = TextStyle(
    color: CyberColors.whiteDim,
    fontSize: 14,
  );

  /// 小号正文（13px, whiteDim）—— 下拉菜单、标签芯片等
  static const TextStyle bodySmall = TextStyle(
    color: CyberColors.whiteDim,
    fontSize: 13,
  );

  /// 小号正文加粗（13px, w600, whiteHigh）
  static const TextStyle bodySmallBold = TextStyle(
    color: CyberColors.whiteHigh,
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle overlineTiny = TextStyle(
    color: CyberColors.whiteDim,
    fontSize: 9,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
  );

  static const TextStyle segmentLabel = TextStyle(
    color: CyberColors.whiteHigh,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
  );

  static const TextStyle teleprompterInlineRead = TextStyle(
    color: CyberColors.neonCyan,
    fontSize: 18,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.5,
    height: 1.0,
  );

  static const TextStyle teleprompterInlineUnread = TextStyle(
    color: CyberColors.whiteMuted,
    fontSize: 18,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    height: 1.0,
  );

  static const TextStyle teleprompterError = TextStyle(
    color: CyberColors.whiteHigh,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  /// 提词器浮层小号错误标题（10px bold）
  static const TextStyle teleprompterErrorTitle = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.bold,
  );

  /// 提词器浮层小号提示文字（9px）
  static const TextStyle teleprompterErrorHint = TextStyle(
    fontSize: 9,
  );

  static const TextStyle teleprompterPlaceholder = TextStyle(
    color: CyberColors.whiteMuted,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle dashboardCounter = TextStyle(
    color: CyberColors.neonCyan,
    fontSize: 22,
    fontFamily: monoFont,
    fontWeight: FontWeight.w900,
  );

  static const TextStyle dashboardSeparator = TextStyle(
    color: CyberColors.whiteSubtle,
    fontSize: 16,
    fontFamily: monoFont,
    fontWeight: FontWeight.w300,
  );

  static const TextStyle captionBold = TextStyle(
    color: CyberColors.whiteDim,
    fontSize: 12,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle captionTight = TextStyle(
    color: CyberColors.whiteDim,
    fontSize: 12,
    height: 1.3,
  );

  static const TextStyle captionComfortable = TextStyle(
    color: CyberColors.whiteDim,
    fontSize: 12,
    height: 1.4,
  );

  static const TextStyle captionHint = TextStyle(
    color: CyberColors.whiteDim,
    fontSize: 11,
    height: 1.5,
  );

  /// 提示/说明文字（12px, whiteDim）
  static const TextStyle caption = TextStyle(
    color: CyberColors.whiteDim,
    fontSize: 12,
  );

  /// 对话框标题（18px, bold）
  /// 使用时通过 copyWith(color: ...) 设置具体颜色
  static const TextStyle dialogTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
  );

  /// 按钮文字（14px, bold）
  static const TextStyle buttonLabel = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.bold,
  );
}
