import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/core/constants/book_constants.dart';
import 'package:yueyou/features/audio/domain/tts_audio_state.dart';
import 'package:yueyou/features/audio/providers/tts_audio_notifier.dart';
import 'package:yueyou/features/library/domain/book_model.dart';
import 'package:yueyou/features/library/providers/bookshelf_provider.dart';
import 'package:yueyou/features/reader/domain/reading_home_view_state.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';

/// 从现有 Reader、TTS 和书架真值源派生听读首页状态。
///
/// 该 Provider 只读组合已有状态，不创建播放会话、不写入进度，也不修改书架
/// 顺序；任何新业务动作都必须继续走原有 Provider API。
final readingHomeViewProvider = Provider<ReadingHomeViewState>((ref) {
  final reader = ref.watch(readerProvider);
  final audio = ref.watch(ttsAudioProvider);
  final shelf = ref.watch(bookshelfProvider);
  final bookId = reader.currentBookId;

  if (bookId == null || reader.sentences.isEmpty) {
    return const ReadingHomeViewState.empty();
  }

  final stateData = _ReadingHomeStateData(
    bookId: bookId,
    bookTitle: _resolveBookTitle(bookId, shelf.shelf),
    chapterTitle: reader.currentChapterTitle,
    currentSentence: reader.currentSentence,
    readingProgress: reader.progress,
    playbackRate: audio.playbackRate,
  );

  return switch (audio) {
    TtsAudioIdle() => _idleState(stateData),
    TtsAudioBuffering(:final progress, :final session) => ReadingHomeViewState(
        status: ReadingHomeStatus.buffering,
        bookId: stateData.bookId,
        bookTitle: stateData.bookTitle,
        chapterTitle: stateData.chapterTitle,
        currentSentence: stateData.currentSentence,
        readingProgress: stateData.readingProgress,
        bufferingProgress: progress,
        fallbackMessage: audio.fallbackMessage,
        playbackRate: stateData.playbackRate,
        session: session,
      ),
    TtsAudioPlaying(:final item) => ReadingHomeViewState(
        status: ReadingHomeStatus.playing,
        bookId: stateData.bookId,
        bookTitle: stateData.bookTitle,
        chapterTitle: stateData.chapterTitle,
        currentSentence: stateData.currentSentence ?? item.textPreview,
        readingProgress: stateData.readingProgress,
        fallbackMessage: audio.fallbackMessage,
        playbackRate: stateData.playbackRate,
        session: item.session,
      ),
    TtsAudioPaused(:final item, :final session) => ReadingHomeViewState(
        status: ReadingHomeStatus.paused,
        bookId: stateData.bookId,
        bookTitle: stateData.bookTitle,
        chapterTitle: stateData.chapterTitle,
        currentSentence: stateData.currentSentence ?? item?.textPreview,
        readingProgress: stateData.readingProgress,
        fallbackMessage: audio.fallbackMessage,
        playbackRate: stateData.playbackRate,
        session: session,
      ),
    TtsAudioError(
      :final message,
      :final recoverable,
      :final session,
    ) =>
      ReadingHomeViewState(
        status: ReadingHomeStatus.recoverableError,
        bookId: stateData.bookId,
        bookTitle: stateData.bookTitle,
        chapterTitle: stateData.chapterTitle,
        currentSentence: stateData.currentSentence,
        readingProgress: stateData.readingProgress,
        errorMessage: message,
        fallbackMessage: audio.fallbackMessage,
        playbackRate: stateData.playbackRate,
        session: session,
        canRecover: recoverable,
      ),
  };
});

ReadingHomeViewState _idleState(_ReadingHomeStateData data) {
  final completed = data.readingProgress >= 1.0;
  return ReadingHomeViewState(
    status: completed ? ReadingHomeStatus.completed : ReadingHomeStatus.ready,
    bookId: data.bookId,
    bookTitle: data.bookTitle,
    chapterTitle: data.chapterTitle,
    currentSentence: data.currentSentence,
    readingProgress: data.readingProgress,
    playbackRate: data.playbackRate,
  );
}

String _resolveBookTitle(String bookId, List<BookModel> shelf) {
  if (bookId == BookConstants.defaultBookKey) {
    return BookConstants.defaultBookTitle;
  }

  for (final book in shelf) {
    if (book.id.toString() == bookId) return book.displayTitle;
  }
  return '当前书籍';
}

final class _ReadingHomeStateData {
  final String bookId;
  final String bookTitle;
  final String chapterTitle;
  final String? currentSentence;
  final double readingProgress;
  final double playbackRate;

  const _ReadingHomeStateData({
    required this.bookId,
    required this.bookTitle,
    required this.chapterTitle,
    required this.currentSentence,
    required this.readingProgress,
    required this.playbackRate,
  });
}
