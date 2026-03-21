import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yueyou/features/reader/providers/reader_provider.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';

/// 赛博 KTV 提词器 - 真·跑马灯版（恒定字号）
/// 🔥 修复：删除 FittedBox，使用固定字号 + 横向滚动
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
      duration: const Duration(milliseconds: 2000),
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
    if (text != _lastText) {
      _lastText = text;
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

        if (reader.ttsEngine.isSpeaking && text.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _startScanAnimation(text);
          });
        }

        // 🔥 修复：删除 FittedBox，使用固定字号 18 + 横向滚动
        return SizedBox(
          height: 40, // 🔥 瘦身：限制高度
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ShaderMask(
                shaderCallback: (bounds) {
                  return LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.3),
                      CyberColors.neonCyan,
                      Colors.white.withOpacity(0.3),
                    ],
                    stops: const [-0.3, 0.0, 0.3],
                    transform: GradientRotation(_scanAnimation.value * 3.14159),
                  ).createShader(bounds);
                },
                blendMode: BlendMode.srcIn,
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18, // 🔥 恒定字号，绝不变化
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
