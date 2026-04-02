import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// 物理音效引擎
/// 使用轻量级触觉反馈替代刺耳的合成音效
class SfxService {
  static final AudioPlayer _mergePlayer = AudioPlayer();
  static const bool _enabled = true;

  static Future<void> init() async {
    // 无需初始化，HapticFeedback 是系统级 API
  }

  /// 触发合并音效 —— 使用轻脆的触觉反馈
  /// 仅在 settings.sound == true 时调用
  static Future<void> playMerge(int mergedValue) async {
    if (!_enabled) return;

    // 战区1.3: 找回合并音效 - 使用更强烈的触觉反馈
    // 所有合并都使用 mediumImpact 确保清晰的反馈
    if (mergedValue <= 64) {
      await HapticFeedback.mediumImpact();
    } else if (mergedValue <= 512) {
      await HapticFeedback.heavyImpact();
    } else {
      // 超大合并：双重震动
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 50));
      await HapticFeedback.heavyImpact();
    }
  }

  static void dispose() {
    _mergePlayer.dispose();
  }
}
