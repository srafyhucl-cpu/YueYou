import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';
import 'package:yueyou/core/config/feature_flags.dart';
import 'package:yueyou/features/audio/domain/tts_audio_state.dart';
import 'package:yueyou/features/audio/providers/tts_audio_notifier.dart';
import 'package:yueyou/features/game_2048/providers/game_provider.dart';
import 'package:yueyou/features/library/providers/bookshelf_provider.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_event.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_growth_engine.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_profile.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_repository.dart';
import 'package:yueyou/features/xiaoyo/services/xiaoyo_local_repository.dart';
import 'package:yueyou/features/xiaoyo/services/xiaoyo_profile_transfer_service.dart';
import 'package:yueyou/features/xiaoyo/providers/xiaoyo_signal_bridge.dart';

/// Xiaoyo 本地 Repository Provider，测试可替换为内存实现。
final xiaoyoRepositoryProvider = Provider<XiaoyoRepository>(
  (ref) => XiaoyoLocalRepository(),
);

/// Xiaoyo Profile 异步状态 Provider。
final xiaoyoProfileProvider =
    AsyncNotifierProvider<XiaoyoProfileNotifier, XiaoyoProfile>(
  XiaoyoProfileNotifier.new,
);

/// 2048 高分合并的瞬时视觉脉冲序号，不持久化、不影响成长。
final xiaoyoVisualPulseProvider = StateProvider<int>((ref) => 0);

/// Xiaoyo Profile 文件转移服务 Provider，测试可替换文件选择器。
final xiaoyoProfileTransferServiceProvider =
    Provider<XiaoyoProfileTransferService>(
  (ref) => XiaoyoProfileTransferService(),
);

/// 领域事件的唯一编排入口，不把成长规则放进 UI 或 Rive 控制器。
class XiaoyoProfileNotifier extends AsyncNotifier<XiaoyoProfile> {
  final XiaoyoGrowthEngine _engine = XiaoyoGrowthEngine();
  late final XiaoyoRepository _repository;

  @override
  Future<XiaoyoProfile> build() {
    _repository = ref.read(xiaoyoRepositoryProvider);
    return _repository.load();
  }

  /// 应用一个事件并在 Profile 变化后持久化。
  Future<XiaoyoGrowthResult?> applyEvent(XiaoyoEvent event) async {
    final current = state.value;
    if (current == null) return null;
    final result = _engine.apply(current, event);
    if (!result.applied) return result;
    try {
      await _repository.save(result.profile);
      state = AsyncData(result.profile);
      return result;
    } catch (error, stackTrace) {
      CyberLogger.captureWarning(
        error,
        stack: stackTrace,
        tag: 'dashboard',
        extra: {'context': 'Xiaoyo Profile 事件落盘失败'},
      );
      return null;
    }
  }

  /// 按用户选择删除或保留某本书的印记。
  Future<bool> removeBookMark(String bookId, {required bool keepMark}) async {
    final current = state.value;
    if (current == null || keepMark) return false;
    final marks =
        current.bookRealmMarks.where((mark) => mark.bookId != bookId).toList();
    if (marks.length == current.bookRealmMarks.length) return false;
    final next = current.copyWith(bookRealmMarks: marks);
    await _repository.save(next);
    state = AsyncData(next);
    return true;
  }

  /// 使用用户确认过的本地 Profile 替换当前状态并持久化。
  Future<bool> replaceProfile(XiaoyoProfile profile) async {
    try {
      final restored =
          await _repository.importBundle(XiaoyoExportBundle(profile));
      state = AsyncData(restored);
      return true;
    } catch (error, stackTrace) {
      CyberLogger.captureWarning(
        error,
        stack: stackTrace,
        tag: 'dashboard',
        extra: {'context': 'Xiaoyo Profile 恢复落盘失败'},
      );
      return false;
    }
  }
}

/// 只在价值系统开关开启时挂载 Reader/TTS 到 Xiaoyo 的单向事件桥。
final xiaoyoSignalBridgeProvider = Provider<XiaoyoSignalBridge>((ref) {
  final bridge = XiaoyoSignalBridge(
    dispatch: (event) async {
      await ref.read(xiaoyoProfileProvider.future);
      await ref.read(xiaoyoProfileProvider.notifier).applyEvent(event);
    },
  );
  if (!FeatureFlags.xiaoyoValueSystem && !FeatureFlags.xiaoyoV2) return bridge;

  if (FeatureFlags.xiaoyoV2) {
    final gameBridge = XiaoyoGameSignalBridge(
      onHighTileMerged: () {
        ref.read(xiaoyoVisualPulseProvider.notifier).state++;
      },
    );
    ref.listen<GameProvider>(gameProvider, (previous, next) {
      gameBridge.onGameChanged(next.lastMergedValue);
    });
  }

  if (FeatureFlags.xiaoyoValueSystem) {
    ref.listen<TtsAudioState>(ttsAudioProvider, (previous, next) {
      if (next case TtsAudioPlaying(:final item)) {
        final reader = ref.read(readerProvider);
        final bookId = reader.currentBookId;
        if (bookId == null) return;
        final book = ref
            .read(bookshelfProvider)
            .shelf
            .where((candidate) => candidate.id.toString() == bookId)
            .firstOrNull;
        bridge.onPlaybackProgress(
          bookId: bookId,
          bookTitle: book?.displayTitle ?? bookId,
          cursor: item.lineIndex,
          progressPercent: reader.progress * 100.0,
        );
        bridge.onBookProgress(
          bookId: bookId,
          bookTitle: book?.displayTitle ?? bookId,
          progress: reader.progress,
        );
      }
    });

    ref.listen<ReaderProvider>(readerProvider, (previous, next) {
      final bookId = next.currentBookId;
      final chapterIndex = next.currentChapterIndex;
      if (bookId == null || chapterIndex == null) return;
      bridge.onReaderChapter(
        bookId: bookId,
        chapterIndex: chapterIndex,
      );
    });
  }

  ref.onDispose(bridge.resetBook);
  return bridge;
});
