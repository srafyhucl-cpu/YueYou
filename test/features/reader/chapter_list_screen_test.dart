import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/library/domain/book_model.dart';
import 'package:yueyou/features/reader/domain/text_parser.dart';
import 'package:yueyou/features/reader/presentation/screens/chapter_list_screen.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';

class _FakeAudioPlayer implements TtsAudioPlayer {
  final StreamController<void> _controller = StreamController<void>.broadcast();

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  @override
  Stream<void> get onPlayerComplete => _controller.stream;

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> setPlaybackRate(double rate) async {}

  @override
  Future<void> setSource(Source source) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}
}

class _FakeWakeLock implements TtsWakeLock {
  @override
  Future<void> disable() async {}

  @override
  Future<void> enable() async {}
}

class _FakeHttpClient implements TtsHttpClient {
  @override
  Future<http.Response> post(Uri url,
      {Map<String, String>? headers, Object? body}) async {
    return http.Response('', 200);
  }
}

Future<ParseResult> _parseBookStub(String rawText) async {
  final lines = rawText
      .split(RegExp(r'\r?\n'))
      .where((line) => line.trim().isNotEmpty)
      .toList();
  return ParseResult(lines, List<int>.generate(lines.length, (index) => index));
}

Future<ReaderProvider> _makeReader() async {
  SharedPreferences.setMockInitialValues({});
  StorageService.resetForTesting();
  await StorageService.init();
  final settings = SettingsProvider()..loadFromStorage();
  settings.storyTts = false;
  final tts = TtsEngineService(
    settings,
    audioPlayer: _FakeAudioPlayer(),
    wakeLock: _FakeWakeLock(),
    httpClient: _FakeHttpClient(),
    delayFn: (_) async {},
  );
  final reader = ReaderProvider(tts, parseBook: _parseBookStub);
  addTearDown(() {
    reader.dispose();
    tts.dispose();
  });
  return reader;
}

Future<ReaderProvider> _makeReaderWithBook() async {
  final reader = await _makeReader();
  const raw = '第一章 开始。\n第二章 发展。\n第三章 终局。\n';
  const chapters = [
    ChapterModel(title: '第一章 开始', lineIndex: 0),
    ChapterModel(title: '第二章 发展', lineIndex: 1),
    ChapterModel(title: '第三章 终局', lineIndex: 2),
  ];
  await reader.loadBook(
    raw,
    bookId: 'chapter_test_book',
    chapters: chapters,
    initialIndex: 1,
    forceIndex: true,
  );
  return reader;
}

Widget _buildApp(ReaderProvider reader, {bool withLauncher = false}) {
  return ChangeNotifierProvider.value(
    value: reader,
    child: MaterialApp(
      home: withLauncher
          ? Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ChapterListScreen(),
                        ),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            )
          : const ChapterListScreen(),
    ),
  );
}

Future<void> _pumpApp(
  WidgetTester tester,
  ReaderProvider reader, {
  bool withLauncher = false,
}) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  await tester.pumpWidget(_buildApp(reader, withLauncher: withLauncher));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChapterListScreen', () {
    testWidgets('空目录时显示占位与 0% 统计', (tester) async {
      final reader = await _makeReader();

      await _pumpApp(tester, reader);

      expect(find.text('章节目录'), findsOneWidget);
      expect(find.text('暂无目录数据'), findsOneWidget);
      expect(find.text('共 0 章 | 阅读进度 0%'), findsOneWidget);
      expect(find.text('正序'), findsOneWidget);
    });

    testWidgets('显示章节统计与当前章节高亮', (tester) async {
      final reader = await _makeReaderWithBook();

      await _pumpApp(tester, reader);

      expect(find.text('共 3 章 | 阅读进度 33%'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);

      final activeTitle = tester.widget<Text>(find.text('第二章 发展'));
      final readTitle = tester.widget<Text>(find.text('第一章 开始'));
      final unreadTitle = tester.widget<Text>(find.text('第三章 终局'));

      expect(activeTitle.style?.color, CyberColors.neonPink);
      expect(readTitle.style?.color, CyberColors.whiteMuted);
      expect(unreadTitle.style?.color, CyberColors.whiteDim);
    });

    testWidgets('点击排序按钮后切换为倒序显示', (tester) async {
      final reader = await _makeReaderWithBook();

      await _pumpApp(tester, reader);

      final firstBefore = tester.getTopLeft(find.text('第一章 开始')).dy;
      final thirdBefore = tester.getTopLeft(find.text('第三章 终局')).dy;
      expect(firstBefore, lessThan(thirdBefore));

      await tester.tap(find.text('正序'));
      await tester.pump();

      expect(find.text('倒序'), findsOneWidget);

      final firstAfter = tester.getTopLeft(find.text('第一章 开始')).dy;
      final thirdAfter = tester.getTopLeft(find.text('第三章 终局')).dy;
      expect(thirdAfter, lessThan(firstAfter));
    });

    testWidgets('点击章节后关闭页面并延迟跳转', (tester) async {
      final reader = await _makeReaderWithBook();

      await _pumpApp(tester, reader, withLauncher: true);

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('章节目录'), findsOneWidget);
      expect(reader.currentIndex, 1);

      await tester.tap(find.text('第三章 终局'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 260));

      expect(find.text('章节目录'), findsNothing);
      expect(reader.currentIndex, 2);
      expect(reader.currentSentence, '第三章 终局。');
    }, timeout: const Timeout(Duration(seconds: 10)));
  });
}
