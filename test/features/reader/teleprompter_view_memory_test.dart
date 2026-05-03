import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/reader/presentation/widgets/teleprompter_view.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import '../../utils/test_utils.dart';

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

  testWidgets('TeleprompterView 高频刷新与毛玻璃渲染边界审计', (tester) async {
    final (reader, tts) = await makeReaderStack();
    addTearDown(() => tts.dispose());

    await tester.runAsync(() async {
      await reader.loadBook(
        '第一句。第二句。第三句。第四句。第五句。',
        bookId: 'mem_test',
        initialIndex: 0,
        forceIndex: true,
      );
    });

    await tester.pumpWidget(_wrapWithProviders(reader));
    await tester.pump();

    expect(find.byType(TeleprompterView), findsOneWidget);

    tts.setEnabled(true);
    await tester.pump();

    // 模拟高频次重建与动画刷新（50 帧 × 32ms ≈ 1.6s）
    for (int i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }

    tts.setEnabled(false);
    tts.dispose();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TeleprompterView), findsOneWidget);
  });
}
