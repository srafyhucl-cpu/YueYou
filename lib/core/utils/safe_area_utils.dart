import 'package:flutter/material.dart';

/// 赛博安全区工具类
/// 提供屏遮挡避让与“呼吸感”留白的常量计算
class SafeAreaUtils {
  /// 基础顶部留白：屏遮挡 (SafeArea) 之上的额外偏移，确保头部 UI 有极致的呼吸感
  static const double topBreathPadding = 24.0;

  /// 获取包含安全区在内的顶部总偏移
  static double getTopOffset(BuildContext context) {
    return MediaQuery.of(context).padding.top + topBreathPadding;
  }
}
