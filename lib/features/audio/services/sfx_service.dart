import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
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
  static Future<void> playMerge({int mergedValue = 0}) async {
    if (!_enabled) return;
    try {
      await _mergePlayer.play(AssetSource('audio/merge.mp3'));

      // 听觉震感分级：根据合并数字大小使用不同强度的震动
      if (mergedValue >= 1024) {
        // 生成 1024 以上：重度震动
        await HapticFeedback.heavyImpact();
      } else if (mergedValue >= 128) {
        // 生成 128 以上：中度震动
        await HapticFeedback.mediumImpact();
      } else {
        // 小数字：轻度震动
        await HapticFeedback.lightImpact();
      }
    } catch (e) {
      debugPrint('⚠️ SFX merge error: $e');
    }
  }

  static void dispose() {
    // 无需释放资源
  }
}
