import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/features/library/providers/bookshelf_provider.dart';
import 'package:yueyou/features/reader/presentation/screens/chapter_list_screen.dart';
import '../../../../shared/widgets/cyber_modal.dart';
import 'voice_waveform.dart';
import 'neon_progress_painter.dart';

/// 阅游赛博控播台 (CyberPlayerConsole)
/// 1:1 复刻 style.css 中的 .cyber-player 与 .bottom-controls 视觉设定
class CyberPlayerConsole extends StatefulWidget {
  const CyberPlayerConsole({super.key});

  @override
  State<CyberPlayerConsole> createState() => _CyberPlayerConsoleState();
}

class _CyberPlayerConsoleState extends State<CyberPlayerConsole>
    with SingleTickerProviderStateMixin {
  late AnimationController _breathController;
  late Animation<double> _breathAnimation;

  @override
  void initState() {
    super.initState();
    // 呼吸动画：2 秒一个周期，无限循环
    _breathController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    _breathAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _breathController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _breathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<ReaderProvider, TtsEngineService, BookshelfProvider>(
      builder: (context, reader, ttsEngine, bookshelf, child) {
        final String novelTitle = _getNovelTitle(reader, bookshelf);
        final String chapterName = reader.currentChapterTitle;

        return Padding(
          padding: const EdgeInsets.only(top: 15),
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
                    borderRadius:
                        BorderRadius.circular(CyberDimensions.radiusL),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: CyberDimensions.blurMedium,
                        sigmaY: CyberDimensions.blurMedium,
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
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
                              color: Color.fromRGBO(0, 0, 0, 0.4),
                              blurRadius: 25,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            VoiceWaveform(
                              isActive: ttsEngine.isSpeaking,
                              color: CyberColors.neonCyan,
                            ),
                            const SizedBox(width: 8),
                            _buildPlayButton(reader, ttsEngine),
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
                                    style: const TextStyle(
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
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            _buildSpeedCapsule(reader, ttsEngine),
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
      },
    );
  }

  Widget _buildPlayButton(ReaderProvider reader, TtsEngineService ttsEngine) {
    final bool isActive =
        ttsEngine.isEnabled && (ttsEngine.isSpeaking || ttsEngine.isBuffering);

    return GestureDetector(
      onTap: () => reader.toggleTTS(),
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
              color: CyberColors.hotPink.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Center(
          child: Icon(
            isActive ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 14,
          ),
        ),
      ),
    );
  }

  String _getNovelTitle(ReaderProvider reader, BookshelfProvider bookshelf) {
    final bookId = reader.currentBookId;
    if (bookId == null) return '阅游';
    final book = bookshelf.shelf.cast<dynamic>().firstWhere(
          (b) => b.id.toString() == bookId,
          orElse: () => null,
        );
    return book?.displayTitle ?? '阅游';
  }

  Widget _buildSpeedCapsule(ReaderProvider reader, TtsEngineService ttsEngine) {
    return GestureDetector(
      onTap: () => reader.cycleSpeed(),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: CyberColors.whiteBorder,
          borderRadius: BorderRadius.circular(CyberDimensions.radiusL),
          border: Border.all(
            color: CyberColors.whiteBorder,
            width: CyberDimensions.borderNormal,
          ),
        ),
        child: Text(
          '${ttsEngine.playbackRate.toStringAsFixed(1)}x',
          style: const TextStyle(
            color: CyberColors.neonCyan,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            fontFamily: 'JetBrains Mono',
          ),
        ),
      ),
    );
  }
}
