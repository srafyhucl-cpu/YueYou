import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/features/reader/presentation/widgets/teleprompter_view.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';

class _FakeHttpClient implements TtsHttpClient {
  final http.Response _response;

  _FakeHttpClient(this._response);

  @override
  Future<http.Response> post(Uri url,
      {Map<String, String>? headers, Object? body}) async {
    return _response;
  }
}

void _mockAudioplayersChannels() {
  const MethodChannel global = MethodChannel('xyz.luan/audioplayers.global');
  const MethodChannel player = MethodChannel('xyz.luan/audioplayers');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(global, (MethodCall call) async => null);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(player, (MethodCall call) async => null);
}

Future<ReaderProvider> _makeReader({TtsHttpClient? httpClient}) async {
  SharedPreferences.setMockInitialValues({});
  StorageService.resetForTesting();
  await StorageService.init();
  _mockAudioplayersChannels();
  final settings = SettingsProvider()..loadFromStorage();
  settings.storyTts = false; // 禁用 TTS，避免播放循环
  return ReaderProvider(TtsEngineService(settings, httpClient: httpClient));
}

Widget _wrapWithProviders(ReaderProvider reader) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: reader),
    ],
    child: const MaterialApp(home: Scaffold(body: TeleprompterView())),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('空数据时显示等待占位文本', (tester) async {
    final reader = await _makeReader();
    await tester.pumpWidget(_wrapWithProviders(reader));

    expect(find.text('等待数据流接入 [ _ ]'), findsOneWidget);
  });

  testWidgets('加载文本后渲染 RichText（isPlaying=false）', (tester) async {
    final reader = await _makeReader();
    await tester.runAsync(() async {
      await reader.loadBook(
        '你好世界。',
        bookId: 't1',
        initialIndex: 0,
        forceIndex: true,
      );
    });

    await tester.pumpWidget(_wrapWithProviders(reader));
    await tester.pump();

    expect(find.byType(RichText), findsOneWidget);
    expect(find.textContaining('你好世界', findRichText: true), findsWidgets);
    // isPlaying=false 时不显示中心指示线
    expect(find.byType(Positioned), findsNWidgets(2)); // 仅左右渐隐遮罩的 Positioned 存在
  });

  testWidgets('TTS 错误提示会自动淡出并清理', (tester) async {
    final reader = await _makeReader(
      httpClient: _FakeHttpClient(http.Response('not found', 404)),
    );
    final service = reader.ttsEngine;
    addTearDown(() {
      reader.dispose();
      service.dispose();
    });

    await tester.runAsync(() async {
      await reader.loadBook(
        '你好世界。',
        bookId: 'teleprompter_error_1',
        initialIndex: 0,
        forceIndex: true,
      );
    });

    await tester.pumpWidget(_wrapWithProviders(reader));
    await service.testConnection();
    await tester.pump();

    expect(
        find.byKey(const ValueKey('teleprompter_error_tip')), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const ValueKey('teleprompter_error_tip')), findsNothing);
    expect(reader.ttsErrorMessage, isNotNull);
  });

  testWidgets('点击错误提示后立即清理错误状态', (tester) async {
    final reader = await _makeReader(
      httpClient: _FakeHttpClient(http.Response('not found', 404)),
    );
    final service = reader.ttsEngine;
    addTearDown(() {
      reader.dispose();
      service.dispose();
    });

    await tester.runAsync(() async {
      await reader.loadBook(
        '你好世界。',
        bookId: 'teleprompter_error_2',
        initialIndex: 0,
        forceIndex: true,
      );
    });

    await tester.pumpWidget(_wrapWithProviders(reader));
    await service.testConnection();
    await tester.pump();

    final tipFinder = find.byKey(const ValueKey('teleprompter_error_tip'));
    expect(tipFinder, findsOneWidget);

    await tester.tap(tipFinder);
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const ValueKey('teleprompter_error_tip')), findsNothing);
    expect(reader.ttsErrorMessage, isNull);
    expect(service.lastError, isNull);
  });
}
