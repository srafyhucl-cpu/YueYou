import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/core/utils/cyber_performance_detector.dart';

void main() {
  group('CyberPerformanceDetector & CyberAnimationLevel', () {
    test('动画等级枚举定义完整', () {
      expect(CyberAnimationLevel.values.length, 3);
      expect(CyberAnimationLevel.high.index, 0);
      expect(CyberAnimationLevel.medium.index, 1);
      expect(CyberAnimationLevel.low.index, 2);
    });

    test('可以获取当前内存占用量', () {
      final memoryBytes = CyberPerformanceDetector.getMemoryUsageBytes();
      expect(memoryBytes, isA<int>());
      // ProcessInfo.currentRss 在非真机/不同环境下可能返回 0 或实际物理常驻内存大小
      expect(memoryBytes, greaterThanOrEqualTo(0));
    });

    test('自适应等级检测返回有效的动画级别', () {
      final level = CyberPerformanceDetector.detectLevel();
      expect(CyberAnimationLevel.values.contains(level), isTrue);
    });
  });
}
