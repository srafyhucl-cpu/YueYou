import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/core/performance/frame_timing_summary.dart';

void main() {
  group('FrameTimingSummary', () {
    test('空样本保持百分位为空，不能伪造实测值', () {
      final summary = FrameTimingSummary.fromSamples(
        const <FrameSample>[],
        frameBudgetMicros: 16667,
      );

      expect(summary.sampleCount, 0);
      expect(summary.buildP50Micros, isNull);
      expect(summary.buildP95Micros, isNull);
      expect(summary.buildP99Micros, isNull);
      expect(summary.rasterP50Micros, isNull);
      expect(summary.rasterP95Micros, isNull);
      expect(summary.rasterP99Micros, isNull);
      expect(summary.slowFrameCount, 0);
      expect(summary.slowFrameRate, 0);
    });

    test('使用 nearest-rank 分别计算 build 与 raster 百分位', () {
      final summary = FrameTimingSummary.fromSamples(
        const <FrameSample>[
          FrameSample(buildMicros: 4000, rasterMicros: 3500),
          FrameSample(buildMicros: 1000, rasterMicros: 500),
          FrameSample(buildMicros: 10000, rasterMicros: 9000),
          FrameSample(buildMicros: 3000, rasterMicros: 2500),
          FrameSample(buildMicros: 2000, rasterMicros: 1500),
        ],
        frameBudgetMicros: 3500,
      );

      expect(summary.sampleCount, 5);
      expect(summary.buildP50Micros, 3000);
      expect(summary.buildP95Micros, 10000);
      expect(summary.buildP99Micros, 10000);
      expect(summary.rasterP50Micros, 2500);
      expect(summary.rasterP95Micros, 9000);
      expect(summary.rasterP99Micros, 9000);
      expect(summary.slowFrameCount, 2);
      expect(summary.slowFrameRate, closeTo(0.4, 0.000001));
    });

    test('任一阶段严格超过预算才计为慢帧', () {
      final summary = FrameTimingSummary.fromSamples(
        const <FrameSample>[
          FrameSample(buildMicros: 16667, rasterMicros: 16667),
          FrameSample(buildMicros: 16668, rasterMicros: 1000),
          FrameSample(buildMicros: 1000, rasterMicros: 16668),
        ],
        frameBudgetMicros: 16667,
      );

      expect(summary.slowFrameCount, 2);
      expect(summary.slowFrameRate, closeTo(2 / 3, 0.000001));
    });

    test('60Hz 与 120Hz 使用统一规则换算微秒预算', () {
      expect(
        FrameTimingSummary.frameBudgetMicrosFor(refreshRateHz: 60),
        16667,
      );
      expect(
        FrameTimingSummary.frameBudgetMicrosFor(refreshRateHz: 120),
        8333,
      );
    });

    test('非法帧预算与刷新率必须快速失败', () {
      expect(
        () => FrameTimingSummary.fromSamples(
          const <FrameSample>[],
          frameBudgetMicros: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => FrameTimingSummary.frameBudgetMicrosFor(refreshRateHz: 0),
        throwsArgumentError,
      );
      expect(
        () => FrameTimingSummary.frameBudgetMicrosFor(
          refreshRateHz: double.nan,
        ),
        throwsArgumentError,
      );
      expect(
        () => FrameTimingSummary.frameBudgetMicrosFor(
          refreshRateHz: double.infinity,
        ),
        throwsArgumentError,
      );
    });

    test('负耗时样本必须快速失败', () {
      expect(
        () => FrameTimingSummary.fromSamples(
          const <FrameSample>[
            FrameSample(buildMicros: -1, rasterMicros: 100),
          ],
          frameBudgetMicros: 16667,
        ),
        throwsArgumentError,
      );
    });

    test('JSON 输出保持字段稳定且空样本为 null', () {
      final summary = FrameTimingSummary.fromSamples(
        const <FrameSample>[],
        frameBudgetMicros: 16667,
      );

      expect(summary.toJson(), <String, Object?>{
        'sampleCount': 0,
        'budgetMicros': 16667,
        'buildP50Micros': null,
        'buildP95Micros': null,
        'buildP99Micros': null,
        'rasterP50Micros': null,
        'rasterP95Micros': null,
        'rasterP99Micros': null,
        'slowFrameCount': 0,
        'slowFrameRate': 0.0,
      });
    });
  });
}
