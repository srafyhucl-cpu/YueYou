import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yueyou/core/performance/frame_timing_summary.dart';

import 'support/profile_frame_collector.dart';

const String _commit = String.fromEnvironment(
  'PERF_COMMIT',
  defaultValue: 'unknown',
);
const String _deviceClass = String.fromEnvironment(
  'PERF_DEVICE_CLASS',
  defaultValue: 'unclassified',
);
const String _buildMode = String.fromEnvironment(
  'PERF_BUILD_MODE',
  defaultValue: 'unknown',
);
const String _refreshRateText = String.fromEnvironment(
  'PERF_REFRESH_RATE_HZ',
  defaultValue: '60',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PERF-0 采集框架可输出脱敏摘要', (tester) async {
    final refreshRateHz = double.tryParse(_refreshRateText);
    expect(refreshRateHz, isNotNull, reason: 'PERF_REFRESH_RATE_HZ 必须是数值');

    final collector = ProfileFrameCollector()..start(binding);
    late final FrameTimingSummary summary;
    try {
      await tester.pumpWidget(const _FrameProbe());
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    } finally {
      summary = collector.stop(refreshRateHz: refreshRateHz!);
    }

    expect(summary.sampleCount, greaterThan(0));
    binding.reportData = <String, dynamic>{
      'schemaVersion': 1,
      'commit': _commit,
      'scenario': 'collector_smoke',
      'deviceClass': _deviceClass,
      'buildMode': _buildMode,
      'refreshRateHz': refreshRateHz,
      'startup': <String, Object?>{
        'systemTotalP50Ms': null,
        'systemTotalP95Ms': null,
        'dashboardReadyP50Ms': null,
      },
      'frames': summary.toJson(),
      'memory': <String, Object?>{
        'startRssMb': null,
        'peakRssMb': null,
        'endRssMb': null,
      },
    };
  });
}

class _FrameProbe extends StatelessWidget {
  const _FrameProbe();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 480),
        tween: Tween<double>(begin: 0, end: 1),
        builder: (context, progress, child) {
          return Transform.translate(
            offset: Offset(progress * 24, 0),
            child: child,
          );
        },
        child: const SizedBox.square(dimension: 24),
      ),
    );
  }
}
