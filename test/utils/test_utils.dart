import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/database/storage_service.dart';

/// 初始化测试环境，设置 mock 值和存储服务
Future<void> initializeTestEnvironment() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  StorageService.resetForTesting();
  await StorageService.init();

  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // Mock path_provider
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (methodCall) async {
      if (methodCall.method == 'getTemporaryDirectory') return '.';
      if (methodCall.method == 'getApplicationDocumentsDirectory') return '.';
      return '.';
    },
  );

  // Mock audioplayers
  messenger.setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers.global'),
    (methodCall) async => null,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers'),
    (methodCall) async => null,
  );

  // Mock wakelock
  messenger.setMockMethodCallHandler(
    const MethodChannel('wakelock_plus'),
    (methodCall) async => null,
  );

  // Mock haptic feedback
  messenger.setMockMethodCallHandler(
    const MethodChannel('flutter/haptic'),
    (methodCall) async => null,
  );

  // Mock platform channel
  messenger.setMockMethodCallHandler(
    const MethodChannel('flutter/platform', JSONMethodCodec()),
    (methodCall) async => null,
  );

  // Mock system sound
  messenger.setMockMethodCallHandler(
    const MethodChannel('flutter/system_sound'),
    (methodCall) async => null,
  );
}
