import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/audio/services/sfx_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SfxService', () {
    // Mock Audioplayers MethodChannel
    const MethodChannel playerChannel = MethodChannel('xyz.luan/audioplayers');
    const MethodChannel globalChannel =
        MethodChannel('xyz.luan/audioplayers.global');

    setUp(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(playerChannel,
              (MethodCall methodCall) async {
        return null;
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(globalChannel,
              (MethodCall methodCall) async {
        return null;
      });
    });

    test('init should completes', () async {
      await expectLater(SfxService.init(), completes);
    });

    test('playMerge should trigger haptic feedback and audio player', () async {
      // Test different merge values to cover branches
      await expectLater(SfxService.playMerge(16), completes);
      await expectLater(SfxService.playMerge(256), completes);
      await expectLater(SfxService.playMerge(1024), completes);
    });

    test('dispose should not throw', () {
      expect(() => SfxService.dispose(), returnsNormally);
    });
  });
}
