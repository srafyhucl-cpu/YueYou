import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';

/// 🔥 赛博 KTV 提词器 - 逐字扫光跑马灯
/// 架构：AnimationController 驱动 ShaderMask 的 gradient stops
/// 时长估算：文字长度 * (1000 / (语速 * 5)) 毫秒
/// 强制 maxLines:1 + fontSize:18 恒定 + 横向滚动
class TeleprompterView extends StatefulWidget {
  const TeleprompterView({super.key});

  @override
  State<TeleprompterView> createState() => _TeleprompterViewState();
}

class _TeleprompterViewState extends State<TeleprompterView>
    with SingleTickerProviderStateMixin {
  late AnimationController _ktvController;
  String _prevText = '';
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _ktvController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
  }

  @override
  void dispose() {
    _ktvController.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// 当句子变化时，重新计算扫光时长并启动动画
  void _onSentenceChanged(String text, double playbackRate) {
    if (text == _prevText) return;
    _prevText = text;

    // 时长 = 文字长度 * (1000 / (语速 * 5)) 毫秒
    final speed = playbackRate.clamp(0.5, 3.0);
    final ms = (text.length * (1000 / (speed * 5))).round().clamp(600, 8000);
    _ktvController.duration = Duration(milliseconds: ms);
    _ktvController.forward(from: 0.0);

    // 自动滚动到起点
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ReaderProvider>(
      builder: (context, reader, _) {
        if (reader.isParsing) {
          return SizedBox(
            height: 40,
            child: Center(
              child: Text(
                "正在连接神经数据链路...",
                style: TextStyle(
                  color: CyberColors.whiteMuted.withOpacity(0.5),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }

        if (reader.sentences.isEmpty) {
          return SizedBox(
            height: 40,
            child: Center(
              child: Text(
                "等待数据流接入 [ _ ]",
                style: TextStyle(
                  color: CyberColors.whiteMuted.withOpacity(0.5),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }

        final String text = reader.currentSentence ?? "";

        // 当 TTS 正在播放且句子变化时，启动 KTV 扫光
        if (reader.ttsEngine.isSpeaking && text.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _onSentenceChanged(text, reader.ttsEngine.playbackRate);
            }
          });
        }

        // 🔥 基础文字组件（恒定字号 18，不可变）
        final textWidget = Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.visible,
          style: TextStyle(
            color: CyberColors.neonCyan.withOpacity(0.85),
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        );

        // 未播放时：直接显示亮色文字，无需 ShaderMask
        final bool isAnimating =
            reader.ttsEngine.isSpeaking && _ktvController.isAnimating;

        return SizedBox(
          height: 40,
          child: Center(
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: isAnimating
                  ? AnimatedBuilder(
                      animation: _ktvController,
                      builder: (context, child) {
                        final double pos = _ktvController.value;
                        return ShaderMask(
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: const [
                                CyberColors.neonCyan,
                                CyberColors.neonCyan,
                                CyberColors.whiteMuted,
                                CyberColors.whiteMuted,
                              ],
                              stops: [
                                0.0,
                                (pos - 0.02).clamp(0.0, 1.0),
                                pos.clamp(0.0, 1.0),
                                1.0,
                              ],
                            ).createShader(bounds);
                          },
                          blendMode: BlendMode.srcIn,
                          child: child!,
                        );
                      },
                      child: textWidget,
                    )
                  : textWidget,
            ),
          ),
        );
      },
    );
  }
}
