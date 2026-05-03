import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/library/domain/book_model.dart';
import 'package:yueyou/features/reader/domain/text_parser.dart';
import 'package:yueyou/features/reader/presentation/screens/chapter_list_screen.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import '../../utils/test_utils.dart';

Future<ReaderProvider> _makeReader() async {
  const parseResult = ParseResult(
    ['第一章 开始。', '内容一。', '第二章 发展。', '内容二。', '第三章 结尾。', '内容三。'],
    [0, 1, 2, 3, 4, 5],
  );

  final (reader, _) = await makeReaderStack(
    parseBook: (_) async => parseResult,
  );
  await reader.loadBook(
    'mock text',
    bookId: 'chapter_test',
    initialIndex: 0,
    forceIndex: true,
    chapters: const [
      ChapterModel(title: 'Chapter 1', lineIndex: 0),
      ChapterModel(title: 'Chapter 2', lineIndex: 2),
      ChapterModel(title: 'Chapter 3', lineIndex: 4),
    ],
  );
  return reader;
}

Widget _wrapWithProviders(ReaderProvider reader) {
  return ProviderScope(
    overrides: [
      readerProvider.overrideWith((ref) => reader),
      ttsEngineProvider.overrideWith((ref) => reader.ttsEngine),
    ],
    child: const MaterialApp(home: ChapterListScreen()),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await initializeTestEnvironment();
  });

  testWidgets('ChapterListScreen 显示章节列表', (tester) async {
    final reader = await _makeReader();
    addTearDown(() => reader.ttsEngine.dispose());

    await tester.pumpWidget(_wrapWithProviders(reader));
    await tester.pump();

    expect(find.text('Chapter 1'), findsOneWidget);
    expect(find.text('Chapter 2'), findsOneWidget);
    expect(find.text('Chapter 3'), findsOneWidget);
  });

  testWidgets('ChapterListScreen 点击章节后关闭页面并延迟跳转', (tester) async {
    final reader = await _makeReader();
    addTearDown(() => reader.ttsEngine.dispose());

    await tester.pumpWidget(_wrapWithProviders(reader));
    await tester.pump();

    await tester.tap(find.text('Chapter 2'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(reader.currentIndex, 2);
  });
}
