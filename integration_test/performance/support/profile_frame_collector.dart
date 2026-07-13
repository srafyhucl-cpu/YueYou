import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:yueyou/core/performance/frame_timing_summary.dart';

/// 把 Flutter 引擎帧回调转换为可测试的纯 Dart 性能样本。
final class ProfileFrameCollector {
  final List<FrameSample> _samples = <FrameSample>[];
  WidgetsBinding? _binding;
  late final TimingsCallback _timingsCallback = _collectTimings;

  bool get isCollecting => _binding != null;
  int get sampleCount => _samples.length;

  void start(WidgetsBinding binding) {
    if (isCollecting) {
      throw StateError('ProfileFrameCollector 已在采集中');
    }

    _samples.clear();
    _binding = binding;
    binding.addTimingsCallback(_timingsCallback);
  }

  FrameTimingSummary stop({required double refreshRateHz}) {
    final binding = _binding;
    if (binding == null) {
      throw StateError('ProfileFrameCollector 尚未开始采集');
    }

    binding.removeTimingsCallback(_timingsCallback);
    _binding = null;
    return FrameTimingSummary.fromSamples(
      _samples,
      frameBudgetMicros: FrameTimingSummary.frameBudgetMicrosFor(
        refreshRateHz: refreshRateHz,
      ),
    );
  }

  void _collectTimings(List<FrameTiming> timings) {
    _samples.addAll(
      timings.map(
        (timing) => FrameSample(
          buildMicros: timing.buildDuration.inMicroseconds,
          rasterMicros: timing.rasterDuration.inMicroseconds,
        ),
      ),
    );
  }
}
