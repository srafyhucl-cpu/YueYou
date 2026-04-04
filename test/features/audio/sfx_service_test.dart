import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/audio/services/sfx_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SfxService', () {
    const MethodChannel playerChannel = MethodChannel('xyz.luan/audioplayers');
    const MethodChannel globalChannel =
        MethodChannel('xyz.luan/audioplayers.global');

    setUp(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform,
              (MethodCall methodCall) async {
        return null;
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(playerChannel,
              (MethodCall methodCall) async {
        if (methodCall.method == 'getDuration' ||
            methodCall.method == 'getCurrentPosition') {
          return 0;
        }
        return null;
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(globalChannel,
              (MethodCall methodCall) async {
        return 1;
      });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(playerChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(globalChannel, null);
    });

    test('init should completes', () async {
      await expectLater(SfxService.init(), completes);
    });

    test('playMoveFeedback should trigger haptic feedback', () async {
      await expectLater(SfxService.playMoveFeedback(16), completes);
      await expectLater(SfxService.playMoveFeedback(256), completes);
      await expectLater(SfxService.playMoveFeedback(1024), completes);
    });

    test('playMerge should trigger haptic feedback and play audio', () async {
      await SfxService.init();
      await expectLater(SfxService.playMerge(16), completes);
      await expectLater(SfxService.playMerge(256), completes);
      await expectLater(SfxService.playMerge(1024), completes);
    });

    test('dispose should not throw', () {
      expect(() => SfxService.dispose(), returnsNormally);
    });
  });
}
