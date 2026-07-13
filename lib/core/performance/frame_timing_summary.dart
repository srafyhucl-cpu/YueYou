/// 单帧在 Flutter build 与 raster 阶段的耗时样本。
final class FrameSample {
  const FrameSample({
    required this.buildMicros,
    required this.rasterMicros,
  });

  final int buildMicros;
  final int rasterMicros;
}

/// 一组帧样本的稳定统计摘要。
///
/// 百分位固定使用 nearest-rank，build 与 raster 分别统计。没有样本时
/// 百分位保持为 `null`，避免把未采集数据误写成实测 0。
final class FrameTimingSummary {
  const FrameTimingSummary._({
    required this.sampleCount,
    required this.frameBudgetMicros,
    required this.buildP50Micros,
    required this.buildP95Micros,
    required this.buildP99Micros,
    required this.rasterP50Micros,
    required this.rasterP95Micros,
    required this.rasterP99Micros,
    required this.slowFrameCount,
  });

  factory FrameTimingSummary.fromSamples(
    Iterable<FrameSample> samples, {
    required int frameBudgetMicros,
  }) {
    if (frameBudgetMicros <= 0) {
      throw ArgumentError.value(
        frameBudgetMicros,
        'frameBudgetMicros',
        '帧预算必须大于 0',
      );
    }

    final snapshot = List<FrameSample>.of(samples, growable: false);
    for (final sample in snapshot) {
      if (sample.buildMicros < 0 || sample.rasterMicros < 0) {
        throw ArgumentError.value(
          sample,
          'samples',
          '帧耗时不能为负数',
        );
      }
    }

    final buildValues = snapshot
        .map((sample) => sample.buildMicros)
        .toList(growable: false)
      ..sort();
    final rasterValues = snapshot
        .map((sample) => sample.rasterMicros)
        .toList(growable: false)
      ..sort();
    final slowFrameCount = snapshot.where((sample) {
      return sample.buildMicros > frameBudgetMicros ||
          sample.rasterMicros > frameBudgetMicros;
    }).length;

    return FrameTimingSummary._(
      sampleCount: snapshot.length,
      frameBudgetMicros: frameBudgetMicros,
      buildP50Micros: _nearestRank(buildValues, 0.50),
      buildP95Micros: _nearestRank(buildValues, 0.95),
      buildP99Micros: _nearestRank(buildValues, 0.99),
      rasterP50Micros: _nearestRank(rasterValues, 0.50),
      rasterP95Micros: _nearestRank(rasterValues, 0.95),
      rasterP99Micros: _nearestRank(rasterValues, 0.99),
      slowFrameCount: slowFrameCount,
    );
  }

  final int sampleCount;
  final int frameBudgetMicros;
  final int? buildP50Micros;
  final int? buildP95Micros;
  final int? buildP99Micros;
  final int? rasterP50Micros;
  final int? rasterP95Micros;
  final int? rasterP99Micros;
  final int slowFrameCount;

  double get slowFrameRate =>
      sampleCount == 0 ? 0.0 : slowFrameCount / sampleCount;

  /// 根据屏幕刷新率换算单个 Flutter 流水阶段的微秒预算。
  static int frameBudgetMicrosFor({required double refreshRateHz}) {
    if (!refreshRateHz.isFinite || refreshRateHz <= 0) {
      throw ArgumentError.value(
        refreshRateHz,
        'refreshRateHz',
        '刷新率必须是大于 0 的有限数值',
      );
    }

    final budget = (Duration.microsecondsPerSecond / refreshRateHz).round();
    if (budget <= 0) {
      throw ArgumentError.value(
        refreshRateHz,
        'refreshRateHz',
        '刷新率过高，无法换算有效微秒预算',
      );
    }
    return budget;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'sampleCount': sampleCount,
        'budgetMicros': frameBudgetMicros,
        'buildP50Micros': buildP50Micros,
        'buildP95Micros': buildP95Micros,
        'buildP99Micros': buildP99Micros,
        'rasterP50Micros': rasterP50Micros,
        'rasterP95Micros': rasterP95Micros,
        'rasterP99Micros': rasterP99Micros,
        'slowFrameCount': slowFrameCount,
        'slowFrameRate': slowFrameRate,
      };

  static int? _nearestRank(List<int> sortedValues, double percentile) {
    if (sortedValues.isEmpty) return null;
    final rank = (percentile * sortedValues.length).ceil();
    final index = (rank - 1).clamp(0, sortedValues.length - 1);
    return sortedValues[index];
  }
}
