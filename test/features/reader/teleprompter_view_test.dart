import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/reader/presentation/widgets/teleprompter_view.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import '../../utils/test_utils.dart';

Future<ReaderProvider> _makeReader({TtsHttpClient? httpClient}) async {
  final (reader, _) = await makeReaderStack(httpClient: httpClient);
  return reader;
}

Widget _wrapWithProviders(ReaderProvider reader) {
  return ProviderScope(
    overrides: [
      readerProvider.overrideWith((ref) => reader),
      ttsEngineProvider.overrideWith((ref) => reader.ttsEngine),
    ],
    child: const MaterialApp(home: Scaffold(body: TeleprompterView())),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await initializeTestEnvironment();
  });

  testWidgets('空数据时显示「数据流未开启」占位文本', (tester) async {
    final reader = await _makeReader();
    addTearDown(() => reader.ttsEngine.dispose());
    await tester.pumpWidget(_wrapWithProviders(reader));
    expect(find.text('数据流未开启'), findsOneWidget);
  });

  testWidgets('加载文本后非播放态渲染当前句子（text 由 ttsState 驱动）', (tester) async {
    final reader = await _makeReader();
    addTearDown(() => reader.ttsEngine.dispose());
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

    // Idle 状态下应显示已加载的当前句子
    expect(find.byType(TeleprompterView), findsOneWidget);
    expect(find.text('数据流未开启'), findsNothing);
    final richText = tester.widget<RichText>(find.byType(RichText));
    expect(richText.text.toPlainText(), contains('你好世界。'));
  });

  testWidgets('testConnection 失败时 ttsErrorMessage 非空', (tester) async {
    final reader = await _makeReader(
      httpClient: FakeHttpClient(
        const TtsHttpResponse(statusCode: 404, body: 'not found'),
      ),
    );
    addTearDown(() => reader.ttsEngine.dispose());

    await tester.runAsync(() async {
      await reader.loadBook(
        '你好世界。',
        bookId: 'teleprompter_error_1',
        initialIndex: 0,
        forceIndex: true,
      );
    });

    await tester.pumpWidget(_wrapWithProviders(reader));
    await reader.ttsEngine.testConnection();
    await tester.pump();

    expect(reader.ttsErrorMessage, isNotNull);
  });

  testWidgets('clearTtsError 清理错误状态', (tester) async {
    final reader = await _makeReader(
      httpClient: FakeHttpClient(
        const TtsHttpResponse(statusCode: 404, body: 'not found'),
      ),
    );
    addTearDown(() => reader.ttsEngine.dispose());

    await tester.runAsync(() async {
      await reader.loadBook(
        '你好世界。',
        bookId: 'teleprompter_error_2',
        initialIndex: 0,
        forceIndex: true,
      );
    });

    await tester.pumpWidget(_wrapWithProviders(reader));
    await reader.ttsEngine.testConnection();
    await tester.pump();

    expect(reader.ttsErrorMessage, isNotNull);

    reader.clearTtsError();
    await tester.pump();

    expect(reader.ttsErrorMessage, isNull);
    expect(reader.ttsEngine.lastError, isNull);
  });
}
