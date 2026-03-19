import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';

/// 阅游赛博控播台 (CyberPlayerConsole)
/// 1:1 复刻 style.css 中的 .cyber-player 与 .bottom-controls 视觉设定
class CyberPlayerConsole extends StatelessWidget {
  const CyberPlayerConsole({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<ReaderProvider, TtsEngineService>(
      builder: (context, reader, ttsEngine, child) {
        return Padding(
          padding: const EdgeInsets.only(top: 15),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xD90A0A0F),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color.fromRGBO(255, 255, 255, 0.1),
                    width: 1,
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
                    _buildPlayButton(reader, ttsEngine),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              reader.currentSentence ?? '神经链路已休眠',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              ttsEngine.isEnabled
                                  ? (ttsEngine.isBuffering
                                      ? '⏳ 神经数据连接中...'
                                      : reader.currentChapterTitle)
                                  : '轻触继续听',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xCC22D3EE),
                                fontSize: 10,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildSpeedCapsule(reader, ttsEngine),
                  ],
                ),
              ),
            ),
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
            colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFEC4899).withOpacity(0.3),
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

  Widget _buildSpeedCapsule(ReaderProvider reader, TtsEngineService ttsEngine) {
    return GestureDetector(
      onTap: () => reader.cycleSpeed(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(255, 255, 255, 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color.fromRGBO(255, 255, 255, 0.12),
            width: 1,
          ),
        ),
        child: Text(
          '${ttsEngine.playbackRate.toStringAsFixed(1)}x',
          style: const TextStyle(
            color: Color(0xFF22D3EE),
            fontSize: 12,
            fontWeight: FontWeight.w900,
            fontFamily: 'JetBrains Mono',
          ),
        ),
      ),
    );
  }
}
