import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';

/// 赛博动画渲染等级
enum CyberAnimationLevel {
  /// 高配：完整赛博朋克特效（多层霓虹光效、物理粒子、复杂阴影、全帧率渲染）
  high,

  /// 中配：基础特效（去除粒子、简化阴影与滤镜）
  medium,

  /// 低配：极简渲染（完全去除光效滤镜，使用纯色与静态元素替代，强制防卡顿）
  low,
}

/// 性能检测与动画等级自适应机制
class CyberPerformanceDetector {
  CyberPerformanceDetector._();

  /// 基于当前内存压力返回推荐的动画等级。
  ///
  /// 自动策略不在启动或设置读取期间执行同步 CPU 跑分；真实帧耗时应由
  /// Profile/现场数据验证，不能用一次微基准推断渲染能力。
  static CyberAnimationLevel detectLevel() {
    if (kIsWeb) {
      // Web 端环境复杂，统一默认为中等，防止多层滤镜卡顿
      return CyberAnimationLevel.medium;
    }

    final memoryBytes = getMemoryUsageBytes();
    CyberLogger.captureMessage(
      '[性能自适应] 内存占用: ${(memoryBytes / 1024 / 1024).toStringAsFixed(1)}MB',
      tag: 'dashboard',
    );

    // 紧急熔断：App 内存占用过高，为防 OOM 直接降为低配
    if (memoryBytes > 250 * 1024 * 1024) {
      return CyberAnimationLevel.low;
    }

    if (memoryBytes > 120 * 1024 * 1024) return CyberAnimationLevel.medium;
    return CyberAnimationLevel.high;
  }

  /// 获取当前 App 常驻内存（Resident Set Size）
  static int getMemoryUsageBytes() {
    try {
      return ProcessInfo.currentRss;
    } catch (_) {
      return 0;
    }
  }
}
