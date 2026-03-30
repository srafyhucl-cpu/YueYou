import 'package:flutter/material.dart';

class CyberColors {
  // 极致的深色背景
  static const Color background = Color(0xFF000000); // 真正的高级黑

  // 赛博/黑客帝国经典的荧光绿（主色调）
  static const Color neonGreen = Color(0xFF00FF41);

  // 赛博朋克必不可少的霓虹粉
  static const Color neonPink = Color(0xFFFE019A);

  // 霓虹紫色
  static const Color neonPurple = Color(0xFF8B5CF6);

  // 霓虹青色
  static const Color neonCyan = Color(0xFF22D3EE);

  // 卡片背景色（带一点透明度的深灰，制造玻璃感）
  static const Color cardBackground = Color(0xFF13141E);
  static const Color surface = Color(0xFF1A1B28);

  // 提词器未读文字的暗色
  static const Color textDim = Color(0xFF4A5568);

  // 毛玻璃深底色（灵动岛 / 顶部工具栏 / 弹窗共用）
  static const Color glassDark = Color(0xD90A0A0F);

  // 播放按钮渐变粉（CyberPlayerConsole 播放按钮起始色）
  static const Color hotPink = Color(0xFFEC4899);

  // 章节列表 / 弹窗背景
  static const Color panelBackground = Color(0xFF0D0E18);

  // 白色语义化透明度
  static const Color whiteHigh = Color(0xD9FFFFFF); // 85%
  static const Color whiteMedium = Color(0x99FFFFFF); // 60%
  static const Color whiteDim = Color(0x8AFFFFFF); // 54%
  static const Color whiteMuted = Color(0x61FFFFFF); // 38%
  static const Color whiteSubtle = Color(0x3DFFFFFF); // 24%
  static const Color whiteFaint = Color(0x14FFFFFF); // 8%
  static const Color whiteBorder = Color(0x1AFFFFFF); // 10%

  // 黑色语义化透明度（阴影 / 遮罩 / overlay）
  static const Color blackOverlay = Color(0xB3000000); // 70%
  static const Color blackShadow = Color(0x80000000); // 50%
  static const Color blackDim = Color(0x8A000000); // 54%

  // 柔和的发光阴影色
  static const Color glowShadow = Color(0x8800FF41);
  static const Color pinkGlow = Color(0x88FE019A);

  // 2048 方块配色 - 提取自旧版style.css的渐变色
  static const Color tile2Start = Color(0xFF43e97b);
  static const Color tile2End = Color(0xFF38f9d7);

  static const Color tile4Start = Color(0xFF00f2fe);
  static const Color tile4End = Color(0xFF4facfe);

  static const Color tile8Start = Color(0xFF4facfe);
  static const Color tile8End = Color(0xFF00c6fb);

  static const Color tile16Start = Color(0xFF0093e9);
  static const Color tile16End = Color(0xFF80d0c7);

  static const Color tile32Start = Color(0xFFa18cd1);
  static const Color tile32End = Color(0xFFfbc2eb);

  static const Color tile64Start = Color(0xFFc471f5);
  static const Color tile64End = Color(0xFFfa71cd);

  static const Color tile128Start = Color(0xFFe040fb);
  static const Color tile128End = Color(0xFF8e24aa);

  static const Color tile256Start = Color(0xFFf857a6);
  static const Color tile256End = Color(0xFFff5858);

  static const Color tile512Start = Color(0xFFf7971e);
  static const Color tile512End = Color(0xFFffd200);

  static const Color tile1024Start = Color(0xFFff6a00);
  static const Color tile1024End = Color(0xFFee0979);

  static const Color tile2048Start = Color(0xFFf12711);
  static const Color tile2048End = Color(0xFFf5af19); // 亮红
  static const Color tile512 = Color(0xFFFFD60A); // 金色

  // 工具色
  static const Color white = Color(0xFFFFFFFF); // 纯白（Canvas 高光专用）
  static const Color transparent = Color(0x00000000); // 透明（Material 背景专用）
  static const Color tileGold = Color(0xFFFFD700); // 传奇金色（square_board 溯源）
  static const Color hackerBlue =
      Color(0xFF00F3FF); // 骇客蓝（规范中的 #00f3ff，吹着天 BGM）
  static const Color tileBlue = Color(0xFF3B82F6); // 方块低数粒子色（tile_widget 溯源）
}
