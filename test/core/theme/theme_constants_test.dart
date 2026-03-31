import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/core/theme/cyber_shadows.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';

/// 主题常量验证测试
/// 确保设计系统的常量值符合预期，防止意外修改
void main() {
  group('CyberColors 常量验证', () {
    test('背景色应为纯黑', () {
      expect(CyberColors.background, equals(const Color(0xFF000000)));
    });

    test('霓虹绿应为赛博朋克经典色', () {
      expect(CyberColors.neonGreen, equals(const Color(0xFF00FF41)));
    });

    test('霓虹粉应为赛博朋克经典色', () {
      expect(CyberColors.neonPink, equals(const Color(0xFFFE019A)));
    });

    test('卡片背景色应为深灰玻璃感', () {
      expect(CyberColors.cardBackground, equals(const Color(0xFF13141E)));
      expect(CyberColors.surface, equals(const Color(0xFF1A1B28)));
    });

    test('毛玻璃深底色应为半透明黑', () {
      expect(CyberColors.glassDark, equals(const Color(0xD90A0A0F)));
    });

    test('白色透明度层级应正确', () {
      expect(CyberColors.whiteHigh, equals(const Color(0xD9FFFFFF)));
      expect(CyberColors.whiteMedium, equals(const Color(0x99FFFFFF)));
      expect(CyberColors.whiteDim, equals(const Color(0x8AFFFFFF)));
      expect(CyberColors.whiteMuted, equals(const Color(0x61FFFFFF)));
      expect(CyberColors.whiteSubtle, equals(const Color(0x3DFFFFFF)));
      expect(CyberColors.whiteFaint, equals(const Color(0x14FFFFFF)));
      expect(CyberColors.whiteBorder, equals(const Color(0x1AFFFFFF)));
    });

    test('2048 方块渐变色应正确', () {
      // 验证所有方块颜色都不为透明
      expect(CyberColors.tile2Start, isNot(equals(Colors.transparent)));
      expect(CyberColors.tile2048End, isNot(equals(Colors.transparent)));
      // 验证金色特殊值
      expect(CyberColors.tileGold, equals(const Color(0xFFFFD700)));
    });
  });

  group('CyberDimensions 尺寸验证', () {
    test('圆角系统应递减', () {
      expect(CyberDimensions.radiusXL, equals(32.0));
      expect(CyberDimensions.radiusL, equals(24.0));
      expect(CyberDimensions.radiusM, equals(16.0));
      expect(CyberDimensions.radiusS, equals(12.0));
      expect(CyberDimensions.radiusXS, equals(2.0));
      // 验证递减关系
      expect(CyberDimensions.radiusXL > CyberDimensions.radiusL, isTrue);
      expect(CyberDimensions.radiusL > CyberDimensions.radiusM, isTrue);
    });

    test('边框系统应合理', () {
      expect(CyberDimensions.borderThick, equals(1.5));
      expect(CyberDimensions.borderNormal, equals(1.0));
      expect(CyberDimensions.borderThin, equals(0.5));
    });

    test('模糊系统应递减', () {
      expect(CyberDimensions.blurStrong, equals(20.0));
      expect(CyberDimensions.blurMedium, equals(15.0));
      expect(CyberDimensions.blurLight, equals(10.0));
      expect(CyberDimensions.blurStrong > CyberDimensions.blurMedium, isTrue);
    });

    test('间距系统应为 8 的倍数', () {
      expect(CyberDimensions.spacingXS, equals(4.0));
      expect(CyberDimensions.spacingS, equals(8.0));
      expect(CyberDimensions.spacingM, equals(16.0));
      expect(CyberDimensions.spacingL, equals(24.0));
      expect(CyberDimensions.spacingXL, equals(32.0));
    });
  });

  group('CyberShadows 阴影验证', () {
    test('标准阴影应存在', () {
      expect(CyberShadows.elevated, isNotNull);
      expect(CyberShadows.floating, isNotNull);
      expect(CyberShadows.subtle, isNotNull);
    });

    test('霓虹光晕工厂方法应工作', () {
      final greenGlow = CyberShadows.neonGlow(color: CyberColors.neonGreen);
      expect(greenGlow, isNotNull);
      expect(greenGlow.length, equals(2));
    });
  });

  group('CyberTextStyles 文本样式验证', () {
    test('字体族应为等宽字体', () {
      expect(CyberTextStyles.monoFont, equals('JetBrains Mono'));
    });

    test('提词器样式应存在', () {
      expect(CyberTextStyles.teleprompterActive, isNotNull);
      expect(CyberTextStyles.teleprompterDim, isNotNull);
    });

    test('2048 数字样式应存在', () {
      expect(CyberTextStyles.gameGridNumber, isNotNull);
    });

    test('提词器激活样式应为霓虹绿', () {
      expect(CyberTextStyles.teleprompterActive.color,
          equals(CyberColors.neonGreen));
    });
  });
}
