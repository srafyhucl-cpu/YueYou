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
}
