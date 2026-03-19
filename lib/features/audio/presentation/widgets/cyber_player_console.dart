import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';

/// 阅游赛博控播台 (CyberPlayerConsole)
/// 1:1 复刻 style.css 中的 .cyber-player 与 .bottom-controls 视觉设定
class CyberPlayerConsole extends StatelessWidget {
  const CyberPlayerConsole({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ReaderProvider>(
      builder: (context, reader, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xDA0A0A0F), // rgba(10, 10, 15, 0.85)
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 25,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: Row(
                  children: [
                    // 左侧：播放/暂停切换按钮
                    _buildPlayButton(reader),
                    
                    const SizedBox(width: 15),

                    // 中间：全息文本信息 (跑马灯效果预留)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "当前章节", // 未来对接章节名
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            reader.currentSentence ?? "神经链路待命...",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 10),

                    // 右侧：倍速切换胶囊 (1:1 复刻 .capsule-speed)
                    _buildSpeedCapsule(reader),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlayButton(ReaderProvider reader) {
    final bool isActive = reader.ttsEngine.isEnabled && (reader.ttsEngine.isSpeaking || reader.ttsEngine.isBuffering);
    
    return GestureDetector(
      onTap: () => reader.toggleTTS(),
      behavior: HitTestBehavior.opaque, // 阻断点击渗透，复刻老代码防误触
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [CyberColors.neonPink, Color(0xFF8B5CF6)], // 复刻 .player-icon 渐变 (Pink to Purple)
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: CyberColors.neonPink.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Center(
          child: Icon(
            isActive ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedCapsule(ReaderProvider reader) {
    return GestureDetector(
      onTap: () => reader.cycleSpeed(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Text(
          "${reader.ttsEngine.playbackRate.toStringAsFixed(1)}x",
          style: const TextStyle(
            color: Color(0xFF22D3EE), // 复刻 .accent-cyan
            fontSize: 12,
            fontWeight: FontWeight.w900,
            fontFamily: 'JetBrains Mono',
          ),
        ),
      ),
    );
  }
}
