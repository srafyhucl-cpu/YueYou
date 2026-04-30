import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/core/config/tts_config.dart' as config;
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/library/domain/book_model.dart';
import 'package:yueyou/features/reader/domain/text_parser.dart';
import 'package:yueyou/features/reader/presentation/screens/chapter_list_screen.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';
import '../../utils/test_utils.dart';

class _FakeHttpClient implements TtsHttpClient {
  final TtsHttpResponse response;

  _FakeHttpClient(this.response);

  @override
  Future<TtsHttpResponse> post(Uri url,
      {Map<String, String>? headers, Object? body}) async {
    return response;
  }

  @override
  Future<void> download(Uri url, String savePath) async {}
}

class _FakeAudioPlayer implements TtsAudioPlayer {
  @override
  Future<void> setSource(Source source) async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setPlaybackRate(double rate) async {}
  @override
  Future<void> setAudioContext(AudioContext context) async {}

  @override
  Stream<void> get onPlayerComplete => const Stream<void>.empty();

  @override
  Future<void> dispose() async {}
}

class _FakeWakeLock implements TtsWakeLock {
  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}
}

Future<ReaderProvider> _makeReader() async {
  const parseResult = ParseResult(
    ['第一章 开始。', '内容一。', '第二章 发展。', '内容二。', '第三章 结尾。', '内容三。'],
    [0, 1, 2, 3, 4, 5],
  );

  final settings = SettingsProvider();
  settings.loadFromStorage();
  settings.voice = 'zh-CN-XiaoxiaoNeural';
  settings.ttsRate = 1.0;
  settings.idleTimeout = 0;
  settings.sound = true;
  settings.storyTts = false;
  settings.ambientVol = 0.5;
  settings.ambientEnabled = false;

  final ttsEngine = TtsEngineService(
    settings,
    config: const config.TtsConfig(serverUrl: 'http://test.com/tts'),
    audioPlayer: _FakeAudioPlayer(),
    wakeLock: _FakeWakeLock(),
    httpClient: _FakeHttpClient(const TtsHttpResponse(
      statusCode: 200,
      body: '{"status": "success", "url": "https://example.com/audio.mp3"}',
    )),
    delayFn: (d) => Future<void>.delayed(Duration.zero),
  );

  final reader = ReaderProvider(
    ttsEngine,
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

/// 使用 Riverpod ProviderScope 包装，覆盖 readerProvider 与 ttsEngineProvider
Widget _wrapWithProviders(ReaderProvider reader) {
  return ProviderScope(
    overrides: [
      readerProvider.overrideWith((ref) => reader),
      ttsEngineProvider.overrideWith((ref) => reader.ttsEngine),
    ],
    child: const MaterialApp(
      home: ChapterListScreen(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await initializeTestEnvironment();
  });

  testWidgets('ChapterListScreen 显示章节列表', (tester) async {
    final reader = await _makeReader();

    await tester.pumpWidget(_wrapWithProviders(reader));
    await tester.pump();

    expect(find.text('Chapter 1'), findsOneWidget);
    expect(find.text('Chapter 2'), findsOneWidget);
    expect(find.text('Chapter 3'), findsOneWidget);
  });

  testWidgets('ChapterListScreen 点击章节后关闭页面并延迟跳转', (tester) async {
    final reader = await _makeReader();

    await tester.pumpWidget(_wrapWithProviders(reader));
    await tester.pump();

    await tester.tap(find.text('Chapter 2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(reader.currentIndex, 2);
  });
}
