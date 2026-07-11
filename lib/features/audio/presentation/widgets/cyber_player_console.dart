import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/core/constants/book_constants.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/features/audio/domain/tts_audio_state.dart';
import 'package:yueyou/features/audio/providers/tts_audio_notifier.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/features/library/domain/book_model.dart';
import 'package:yueyou/features/library/providers/bookshelf_provider.dart';
import 'package:yueyou/features/reader/presentation/screens/chapter_list_screen.dart';
import 'package:yueyou/shared/widgets/cyber_modal.dart';
import 'voice_waveform.dart';
import 'neon_progress_painter.dart';

/// 解析当前 bookId 对应的小说标题。
///
/// P1-3：抽出为顶层纯函数，便于直接单元测试覆盖默认书 key 特例。
/// - `null` → 兜底"阅游"（无书状态）；
/// - 默认书 key（'xiyouji'）→ 直接返回内置常量，绕过书架 id 比对；
/// - 普通书：在 [shelf] 中按 `id.toString() == bookId` 匹配。
@visibleForTesting
String resolveNovelTitle(String? bookId, List<BookModel> shelf) {
  if (bookId == null) return '阅游';
  if (bookId == BookConstants.defaultBookKey) {
    return BookConstants.defaultBookTitle;
  }
  for (final book in shelf) {
    if (book.id.toString() == bookId) {
      return book.displayTitle;
    }
  }
  return '阅游';
}

/// 阅游赛博控播台 (CyberPlayerConsole)
/// 1:1 复刻 style.css 中的 .cyber-player 与 .bottom-controls 视觉设定
class CyberPlayerConsole extends ConsumerStatefulWidget {
  const CyberPlayerConsole({super.key});

  @override
  ConsumerState<CyberPlayerConsole> createState() => _CyberPlayerConsoleState();
}

class _CyberPlayerConsoleState extends ConsumerState<CyberPlayerConsole>
    with SingleTickerProviderStateMixin {
  late AnimationController _breathController;
  late Animation<double> _breathAnimation;

  /// P0-B：呼吸动画与 TTS 状态联动的引用 CurvedAnimation，仅创建一次避免泄漏
  late final CurvedAnimation _breathCurve;

  @override
  void initState() {
    super.initState();
    // 呼吸动画：2 秒一个周期
    // P0-B：不再 initState 即 repeat，改由 build 阶段根据 TTS 是否激活精准启停，
    // 避免在 TTS 完全空闲时仍持续 60fps 触发 NeonProgressPainter 全树重绘。
    _breathController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _breathCurve = CurvedAnimation(
      parent: _breathController,
      curve: Curves.easeInOut,
    );
    _breathAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(_breathCurve);
  }

  /// 根据 TTS 是否处于活跃状态（播放/缓冲）启停呼吸动画。
  /// idle/paused/error 时停止，避免无意义的 60fps 重绘消耗 GPU。
  void _syncBreath(bool isActive) {
    if (isActive) {
      if (!_breathController.isAnimating) {
        _breathController.repeat();
      }
    } else {
      if (_breathController.isAnimating) {
        _breathController.stop();
      }
    }
  }

  @override
  void dispose() {
    _breathCurve.dispose();
    _breathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reader = ref.watch(readerProvider);
    final ttsState = ref.watch(ttsAudioProvider);
    final bookshelf = ref.watch(bookshelfProvider);

    final String novelTitle = _getNovelTitle(reader, bookshelf);
    final String chapterName = reader.currentChapterTitle;
    final bool isPlaying = switch (ttsState) {
      TtsAudioPlaying() => true,
      TtsAudioIdle() ||
      TtsAudioBuffering() ||
      TtsAudioPaused() ||
      TtsAudioError() =>
        false,
    };
    // P0-B：仅在 TTS 实际有声音输出时驱动呼吸动画
    final bool breathActive = switch (ttsState) {
      TtsAudioPlaying() || TtsAudioBuffering() => true,
      TtsAudioIdle() || TtsAudioPaused() || TtsAudioError() => false,
    };
    _syncBreath(breathActive);

    return Padding(
      padding: const EdgeInsets.only(top: CyberDimensions.spacingM),
      child: Stack(
        children: [
          GestureDetector(
            onTap: () {
              showCyberModal(
                context: context,
                child: const ChapterListScreen(),
              );
            },
            behavior: HitTestBehavior.opaque,
            child: AnimatedBuilder(
              animation: _breathAnimation,
              builder: (context, child) {
                return CustomPaint(
                  painter: NeonProgressPainter(
                    progress: reader.progress,
                    color: CyberColors.neonCyan,
                    strokeWidth: 2.5,
                    animationValue: _breathAnimation.value,
                  ),
                  child: child,
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(CyberDimensions.radiusL),
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: CyberDimensions.blurMedium,
                    sigmaY: CyberDimensions.blurMedium,
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: CyberDimensions.spacingM,
                      vertical: CyberDimensions.spacingS,
                    ),
                    decoration: BoxDecoration(
                      color: CyberColors.glassDark,
                      borderRadius:
                          BorderRadius.circular(CyberDimensions.radiusL),
                      border: Border.all(
                        color: CyberColors.whiteBorder,
                        width: CyberDimensions.borderNormal,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: CyberColors.blackShadow,
                          blurRadius: CyberDimensions.shadowBlurConsole,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        VoiceWaveform(
                          isActive: isPlaying,
                          color: CyberColors.neonCyan,
                        ),
                        const SizedBox(width: 8),
                        _buildPlayButton(reader, ttsState),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '《$novelTitle》',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: CyberTextStyles.caption.copyWith(
                                  color: CyberColors.whiteMedium,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                chapterName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: CyberTextStyles.bodySmallBold.copyWith(
                                  color: CyberColors.whiteHigh,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        _buildSpeedCapsule(reader, ttsState.playbackRate),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayButton(ReaderProvider reader, TtsAudioState ttsState) {
    final bool isActive = switch (ttsState) {
      TtsAudioPlaying() || TtsAudioBuffering() => true,
      TtsAudioIdle() || TtsAudioPaused() || TtsAudioError() => false,
    };

    return GestureDetector(
      onTap: () {
        _handlePlayTap(reader, ttsState);
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [CyberColors.hotPink, CyberColors.neonPurple],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: CyberColors.hotPink.withValues(alpha: 0.3),
              blurRadius: CyberDimensions.blurLight,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Icon(
            isActive ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: CyberColors.white,
            size: 14,
          ),
        ),
      ),
    );
  }

  void _handlePlayTap(ReaderProvider reader, TtsAudioState ttsState) {
    final audio = ref.read(ttsAudioProvider.notifier);
    if (reader.currentBookId == null || reader.sentences.isEmpty) {
      audio.setBusinessError('无法开启 TTS：请先导入书籍');
      return;
    }

    switch (ttsState) {
      case TtsAudioPlaying() || TtsAudioBuffering():
        audio.pause();
      case TtsAudioIdle() || TtsAudioPaused():
        audio.play();
      case TtsAudioError():
        audio.recover();
    }
  }

  String _getNovelTitle(ReaderProvider reader, BookshelfProvider bookshelf) {
    return resolveNovelTitle(reader.currentBookId, bookshelf.shelf);
  }

  Widget _buildSpeedCapsule(ReaderProvider reader, double playbackRate) {
    return GestureDetector(
      onTap: () => ref.read(ttsAudioProvider.notifier).cycleSpeed(),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CyberDimensions.spacingMS,
          vertical: CyberDimensions.spacingS,
        ),
        decoration: BoxDecoration(
          color: CyberColors.whiteBorder,
          borderRadius: BorderRadius.circular(CyberDimensions.radiusL),
          border: Border.all(
            color: CyberColors.whiteBorder,
            width: CyberDimensions.borderNormal,
          ),
        ),
        child: Text(
          '${playbackRate.toStringAsFixed(1)}x',
          style: CyberTextStyles.captionBold.copyWith(
            color: CyberColors.neonCyan,
            fontWeight: FontWeight.w900,
            fontFamily: CyberTextStyles.monoFont,
          ),
        ),
      ),
    );
  }
}
