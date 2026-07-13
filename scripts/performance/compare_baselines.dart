import 'dart:convert';
import 'dart:io';

/// 一份由 PERF-0-B PowerShell 采集器生成的设备基线清单。
final class BaselineReport {
  final int schemaVersion;
  final String commit;
  final String scenario;
  final String deviceClass;
  final String buildMode;
  final double refreshRateHz;
  final List<Map<String, dynamic>> runs;

  const BaselineReport({
    required this.schemaVersion,
    required this.commit,
    required this.scenario,
    required this.deviceClass,
    required this.buildMode,
    required this.refreshRateHz,
    required this.runs,
  });

  factory BaselineReport.fromJson(Map<String, dynamic> json) {
    final schemaVersion = (json['schemaVersion'] as num?)?.toInt();
    final commit = json['commit'];
    final scenario = json['scenario'];
    final deviceClass = json['deviceClass'];
    final buildMode = json['buildMode'];
    final refreshRateHz = (json['refreshRateHz'] as num?)?.toDouble();
    final runs = json['runs'];
    if (schemaVersion != 1 ||
        commit is! String ||
        scenario is! String ||
        deviceClass is! String ||
        buildMode is! String ||
        refreshRateHz == null ||
        !refreshRateHz.isFinite ||
        refreshRateHz <= 0 ||
        runs is! List) {
      throw const FormatException('基线清单缺少固定元数据或 runs 数组');
    }
    final typedRuns = runs
        .whereType<Map<dynamic, dynamic>>()
        .map((run) => run.map((key, value) => MapEntry(key.toString(), value)))
        .toList(growable: false);
    if (typedRuns.isEmpty) {
      throw const FormatException('基线清单没有有效采集轮次');
    }
    return BaselineReport(
      schemaVersion: 1,
      commit: commit,
      scenario: scenario,
      deviceClass: deviceClass,
      buildMode: buildMode,
      refreshRateHz: refreshRateHz,
      runs: typedRuns,
    );
  }
}

/// 在同一设备档位、刷新率和场景下比较两份基线。
final class BaselineComparison {
  final String status;
  final String reason;
  final Map<String, dynamic> metrics;

  const BaselineComparison({
    required this.status,
    required this.reason,
    required this.metrics,
  });

  factory BaselineComparison.from(
    BaselineReport before,
    BaselineReport after,
  ) {
    if (before.deviceClass != after.deviceClass ||
        before.scenario != after.scenario ||
        before.buildMode != after.buildMode ||
        before.refreshRateHz != after.refreshRateHz) {
      return const BaselineComparison(
        status: 'rejected',
        reason: '设备档位、场景、构建模式或刷新率不一致，禁止比较',
        metrics: <String, dynamic>{},
      );
    }

    final beforeFrames = _frameMetricsFromReport(before);
    final afterFrames = _frameMetricsFromReport(after);
    if (beforeFrames == null || afterFrames == null) {
      return const BaselineComparison(
        status: 'insufficient_evidence',
        reason: '一侧或两侧缺少可比较的帧统计字段',
        metrics: <String, dynamic>{},
      );
    }
    return BaselineComparison(
      status: 'comparable',
      reason: '同设备档位、场景、构建模式和刷新率，可进行指标对照',
      metrics: <String, dynamic>{
        'buildP95Micros': _MetricDelta.from(
          beforeFrames.buildP95Micros,
          afterFrames.buildP95Micros,
        ).toJson(),
        'rasterP95Micros': _MetricDelta.from(
          beforeFrames.rasterP95Micros,
          afterFrames.rasterP95Micros,
        ).toJson(),
        'slowFrameRate': _MetricDelta.from(
          beforeFrames.slowFrameRate,
          afterFrames.slowFrameRate,
        ).toJson(),
      },
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'status': status,
        'reason': reason,
        'metrics': metrics,
      };

  static _FrameMetrics? _frameMetricsFromRun(Map<String, dynamic> run) {
    final frames = run['frames'];
    if (frames is! Map) return null;
    final build = _asFiniteDouble(frames['buildP95Micros']);
    final raster = _asFiniteDouble(frames['rasterP95Micros']);
    final slow = _asFiniteDouble(frames['slowFrameRate']);
    if (build == null || raster == null || slow == null) return null;
    return _FrameMetrics(
      buildP95Micros: build,
      rasterP95Micros: raster,
      slowFrameRate: slow,
    );
  }

  static _FrameMetrics? _frameMetricsFromReport(BaselineReport report) {
    final metrics = report.runs
        .map(_frameMetricsFromRun)
        .whereType<_FrameMetrics>()
        .toList(growable: false);
    if (metrics.isEmpty) return null;
    return _FrameMetrics(
      buildP95Micros: _median(metrics.map((item) => item.buildP95Micros)),
      rasterP95Micros: _median(metrics.map((item) => item.rasterP95Micros)),
      slowFrameRate: _median(metrics.map((item) => item.slowFrameRate)),
    );
  }

  static double? _asFiniteDouble(Object? value) {
    final number = value is num ? value.toDouble() : null;
    return number != null && number.isFinite ? number : null;
  }

  static double _median(Iterable<double> values) {
    final sorted = values.toList()..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }
}

final class _FrameMetrics {
  final double buildP95Micros;
  final double rasterP95Micros;
  final double slowFrameRate;

  const _FrameMetrics({
    required this.buildP95Micros,
    required this.rasterP95Micros,
    required this.slowFrameRate,
  });
}

final class _MetricDelta {
  final double before;
  final double after;
  final double delta;
  final double? relativeChange;

  const _MetricDelta({
    required this.before,
    required this.after,
    required this.delta,
    required this.relativeChange,
  });

  factory _MetricDelta.from(double before, double after) => _MetricDelta(
        before: before,
        after: after,
        delta: after - before,
        relativeChange: before == 0 ? null : (after - before) / before,
      );

  Map<String, double?> toJson() => <String, double?>{
        'before': before,
        'after': after,
        'delta': delta,
        'relativeChange': relativeChange,
      };
}

Future<void> main(List<String> arguments) async {
  try {
    final paths = _parseArguments(arguments);
    final before = BaselineReport.fromJson(
      jsonDecode(await File(paths['before']!).readAsString())
          as Map<String, dynamic>,
    );
    final after = BaselineReport.fromJson(
      jsonDecode(await File(paths['after']!).readAsString())
          as Map<String, dynamic>,
    );
    final result = BaselineComparison.from(before, after);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
    if (result.status != 'comparable') exitCode = 2;
  } on Object catch (error) {
    stderr.writeln('PERF-0-B 基线比较失败：$error');
    exitCode = 1;
  }
}

Map<String, String> _parseArguments(List<String> arguments) {
  final values = <String, String>{};
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument != '--before' && argument != '--after') {
      throw FormatException('不支持的参数：$argument');
    }
    if (index + 1 >= arguments.length) {
      throw FormatException('参数缺少路径：$argument');
    }
    values[argument.substring(2)] = arguments[++index];
  }
  if (!values.containsKey('before') || !values.containsKey('after')) {
    throw const FormatException('必须同时提供 --before 和 --after');
  }
  return values;
}
