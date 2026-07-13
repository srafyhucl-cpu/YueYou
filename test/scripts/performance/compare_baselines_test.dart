import 'package:flutter_test/flutter_test.dart';

import '../../../scripts/performance/compare_baselines.dart';

Map<String, dynamic> _report({
  String deviceClass = 'android_mid_60',
  double refreshRateHz = 60,
  Object? frames = const <String, Object?>{
    'buildP95Micros': 8000,
    'rasterP95Micros': 9000,
    'slowFrameRate': 0.02,
  },
}) =>
    <String, dynamic>{
      'schemaVersion': 1,
      'commit': 'commit-$deviceClass',
      'scenario': 'collector_smoke',
      'deviceClass': deviceClass,
      'buildMode': 'profile',
      'refreshRateHz': refreshRateHz,
      'runs': <Map<String, dynamic>>[
        <String, dynamic>{'frames': frames},
      ],
    };

void main() {
  test('同设备基线比较输出帧指标差异', () {
    final before = BaselineReport.fromJson(_report());
    final after = BaselineReport.fromJson(
      _report(
        frames: const <String, Object?>{
          'buildP95Micros': 7000,
          'rasterP95Micros': 10000,
          'slowFrameRate': 0.01,
        },
      ),
    );

    final result = BaselineComparison.from(before, after);

    expect(result.status, 'comparable');
    expect(
      result.metrics['buildP95Micros']['delta'],
      -1000,
    );
    expect(
      result.metrics['rasterP95Micros']['delta'],
      1000,
    );
  });

  test('设备或刷新率不一致时拒绝比较', () {
    final before = BaselineReport.fromJson(_report());
    final after = BaselineReport.fromJson(
      _report(deviceClass: 'android_high_120', refreshRateHz: 120),
    );

    final result = BaselineComparison.from(before, after);

    expect(result.status, 'rejected');
    expect(result.metrics, isEmpty);
  });

  test('缺少帧统计时标记证据不足，不生成零值结论', () {
    final before = BaselineReport.fromJson(_report(frames: null));
    final after = BaselineReport.fromJson(_report());

    final result = BaselineComparison.from(before, after);

    expect(result.status, 'insufficient_evidence');
    expect(result.metrics, isEmpty);
  });

  test('基线清单缺少 runs 时拒绝解析', () {
    final invalid = _report()..remove('runs');

    expect(
      () => BaselineReport.fromJson(invalid),
      throwsA(isA<FormatException>()),
    );
  });
}
