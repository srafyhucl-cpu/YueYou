import 'package:flutter/services.dart';

/// 物理音效引擎
/// 使用轻量级触觉反馈替代刺耳的合成音效
class SfxService {
  static Future<void> init() async {
    // 无需初始化，HapticFeedback 是系统级 API
  }

  /// 触发合并音效 —— 使用轻脆的触觉反馈
  /// 仅在 settings.sound == true 时调用
  static Future<void> playMerge() async {
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {
      // 忽略不支持触觉反馈的设备
    }
  }

  static void dispose() {
    // 无需释放资源
  }
}
