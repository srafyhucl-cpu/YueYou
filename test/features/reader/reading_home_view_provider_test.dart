import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/audio/domain/tts_audio_state.dart';
import 'package:yueyou/features/audio/providers/tts_audio_notifier.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/library/domain/book_model.dart';
import 'package:yueyou/features/library/providers/bookshelf_provider.dart';
import 'package:yueyou/features/reader/domain/reading_home_view_state.dart';
import 'package:yueyou/features/reader/providers/reading_home_view_provider.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';

import '../../utils/test_utils.dart';

class _FakeTtsAudioNotifier extends Notifier<TtsAudioState>
    implements TtsAudioNotifier {
  TtsAudioState _initial = const TtsAudioIdle(
    playbackRate: 1.0,
    fallbackMessage: null,
  );

  @override
  TtsAudioState build() => _initial;

  void setStateForTesting(TtsAudioState next) {
    state = next;
  }

  @override
  void noSuchMethod(Invocation invocation) {}
}

void main() {
  test('Provider 从现有真值源派生七态听读状态', () async {
    await initializeTestEnvironment();
    final settings = makeSettings();
    final engine = makeTtsEngine(settings);
    final reader = ReaderProvider(engine);
    await reader.loadPreparedBook(
      const ['第一句', '第二句'],
      bookId: '7',
      chapters: const [ChapterModel(title: '第一章', lineIndex: 0)],
    );
    final shelf = BookshelfProvider()
      ..setShelfForTesting(const [
        BookModel(id: 7, title: '测试书.txt', total: 2),
      ]);
    final fakeAudio = _FakeTtsAudioNotifier();
    final container = ProviderContainer(
      overrides: [
        readerProvider.overrideWith((ref) => reader),
        bookshelfProvider.overrideWith((ref) => shelf),
        ttsAudioProvider.overrideWith(() => fakeAudio),
      ],
    );
    addTearDown(() {
      container.dispose();
      engine.dispose();
    });

    expect(container.read(readingHomeViewProvider).status,
        ReadingHomeStatus.ready);
    expect(container.read(readingHomeViewProvider).bookTitle, '测试书');

    fakeAudio.setStateForTesting(const TtsAudioBuffering(
      bufferedCount: 1,
      targetCount: 6,
      progress: 0.5,
      session: 1,
      playbackRate: 1.2,
      fallbackMessage: null,
    ));
    expect(container.read(readingHomeViewProvider).status,
        ReadingHomeStatus.buffering);

    fakeAudio.setStateForTesting(const TtsAudioPlaying(
      item: TtsAudioSnapshot(
        id: 1,
        session: 2,
        lineIndex: 0,
        title: '第一章',
        textPreview: '第一句',
      ),
      bufferedCount: 1,
      targetCount: 6,
      playbackRate: 1.2,
      fallbackMessage: null,
    ));
    expect(container.read(readingHomeViewProvider).status,
        ReadingHomeStatus.playing);

    fakeAudio.setStateForTesting(const TtsAudioPaused(
      item: null,
      bufferedCount: 1,
      targetCount: 6,
      session: 2,
      playbackRate: 1.2,
      fallbackMessage: null,
    ));
    expect(container.read(readingHomeViewProvider).status,
        ReadingHomeStatus.paused);

    fakeAudio.setStateForTesting(const TtsAudioError(
      type: TtsAudioErrorType.network,
      message: '网络暂时不可用',
      timestamp: 1,
      recoverable: true,
      session: 2,
      playbackRate: 1.2,
      fallbackMessage: null,
    ));
    final error = container.read(readingHomeViewProvider);
    expect(error.status, ReadingHomeStatus.recoverableError);
    expect(error.canRecover, isTrue);

    fakeAudio.setStateForTesting(const TtsAudioIdle(
      playbackRate: 1.0,
      fallbackMessage: null,
    ));
    await reader.jumpTo(1);
    expect(container.read(readingHomeViewProvider).status,
        ReadingHomeStatus.completed);
  });
}
