import 'dart:developer';
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

  /// 评估设备性能并返回推荐的动画等级
  ///
  /// 划分标准（CPU 微基准测试 + App 当前内存占用）：
  /// 1. CPU 评估：
  ///    - 耗时 <= 30ms -> CPU 强劲
  ///    - 30ms < 耗时 <= 80ms -> CPU 中等
  ///    - 耗时 > 80ms -> CPU 偏弱
  ///
  /// 2. 内存评估 (当前 App 常驻内存 RSS)：
  ///    - 内存 <= 120MB -> 状态健康
  ///    - 120MB < 内存 <= 250MB -> 警戒状态
  ///    - 内存 > 250MB -> 内存危急 (自动降级为 Low)
  static CyberAnimationLevel detectLevel() {
    if (kIsWeb) {
      // Web 端环境复杂，统一默认为中等，防止多层滤镜卡顿
      return CyberAnimationLevel.medium;
    }

    final memoryBytes = getMemoryUsageBytes();
    final cpuTimeMs = runCpuBenchmark();

    CyberLogger.captureMessage(
      '[性能自适应] CPU 评分: ${cpuTimeMs}ms, 内存占用: ${(memoryBytes / 1024 / 1024).toStringAsFixed(1)}MB',
      tag: 'dashboard',
    );

    // 紧急熔断：App 内存占用过高，为防 OOM 直接降为低配
    if (memoryBytes > 250 * 1024 * 1024) {
      return CyberAnimationLevel.low;
    }

    // 判定等级
    if (cpuTimeMs <= 30) {
      // 内存也健康的情况
      if (memoryBytes <= 120 * 1024 * 1024) {
        return CyberAnimationLevel.high;
      }
      return CyberAnimationLevel.medium;
    } else if (cpuTimeMs <= 80) {
      return CyberAnimationLevel.medium;
    } else {
      return CyberAnimationLevel.low;
    }
  }

  /// 获取当前 App 常驻内存（Resident Set Size）
  static int getMemoryUsageBytes() {
    try {
      return ProcessInfo.currentRss;
    } catch (_) {
      return 0;
    }
  }

  /// 执行 CPU 微基准测试评估算力 (执行 1,000,000 次无意义的数学运算)
  /// 返回执行所耗毫秒数
  static int runCpuBenchmark() {
    final sw = Stopwatch()..start();
    int a = 0;
    for (int i = 0; i < 1000000; i++) {
      a = (a + i) % 9999;
    }
    sw.stop();
    // 打印一下保证变量 a 不被编译器激进优化清除
    Timeline.instantSync('CPU_Benchmark_Result', arguments: {'a': a});
    return sw.elapsedMilliseconds;
  }
}
