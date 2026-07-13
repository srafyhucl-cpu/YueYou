import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/performance/support/profile_frame_collector.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  group('ProfileFrameCollector', () {
    test('start 与 stop 成对注册并释放帧回调', () {
      final collector = ProfileFrameCollector();

      collector.start(binding);
      expect(collector.isCollecting, isTrue);
      expect(collector.sampleCount, 0);

      final summary = collector.stop(refreshRateHz: 60);
      expect(collector.isCollecting, isFalse);
      expect(summary.sampleCount, 0);
      expect(summary.frameBudgetMicros, 16667);
    });

    test('重复 start 必须快速失败且仍可正常停止', () {
      final collector = ProfileFrameCollector()..start(binding);

      expect(() => collector.start(binding), throwsStateError);

      collector.stop(refreshRateHz: 60);
      expect(collector.isCollecting, isFalse);
    });

    test('未 start 时 stop 必须快速失败', () {
      final collector = ProfileFrameCollector();

      expect(
        () => collector.stop(refreshRateHz: 60),
        throwsStateError,
      );
    });
  });
}
