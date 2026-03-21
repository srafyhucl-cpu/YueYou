import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';

/// 赛博 KTV 提词器 - 流光跑马灯高亮版
/// 使用 ShaderMask 实现扫光效果，让高亮像水流一样滑过文字
class TeleprompterView extends StatefulWidget {
  const TeleprompterView({super.key});

  @override
  State<TeleprompterView> createState() => _TeleprompterViewState();
}

class _TeleprompterViewState extends State<TeleprompterView>
    with SingleTickerProviderStateMixin {
  late AnimationController _scanController;
  late Animation<double> _scanAnimation;
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000), // 基础扫光时长
    );
    _scanAnimation = Tween<double>(begin: -1.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanController, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  void _startScanAnimation(String text) {
    // 如果文本变化，重新计算动画时长
    if (text != _lastText) {
      _lastText = text;
      // 根据文本长度动态调整扫光速度
      final duration = (text.length * 80).clamp(800, 3000).toInt();
      _scanController.duration = Duration(milliseconds: duration);
    }

    _scanController.reset();
    _scanController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ReaderProvider>(
      builder: (context, reader, _) {
        if (reader.isParsing) {
          return const Center(
            child: Text(
              "正在连接神经数据链路...",
              style: TextStyle(
                color: Colors.white30,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }

        if (reader.sentences.isEmpty) {
          return Center(
            child: Text(
              "等待数据流接入 [ _ ]",
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }

        final String text = reader.currentSentence ?? "";

        // 当 TTS 播放时启动扫光动画
        if (reader.ttsEngine.isSpeaking && text.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _startScanAnimation(text);
          });
        }

        return Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ShaderMask(
              shaderCallback: (bounds) {
                return LinearGradient(
                  colors: [
                    // 暗色未读文字
                    Colors.white.withOpacity(0.3),
                    // 霓虹青色高亮
                    CyberColors.neonCyan,
                    // 暗色未读文字
                    Colors.white.withOpacity(0.3),
                  ],
                  stops: const [-0.3, 0.0, 0.3],
                  transform: GradientRotation(_scanAnimation.value * 3.14159),
                ).createShader(bounds);
              },
              blendMode: BlendMode.srcIn,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  style: const TextStyle(
                    color: Colors.white, // 这里会被 ShaderMask 覆盖
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
