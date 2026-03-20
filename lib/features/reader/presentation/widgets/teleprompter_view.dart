import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/reader_provider.dart';

/// 提词器核心展示层
/// 单行横向滚动，适中字体，无点击交互
class TeleprompterView extends StatelessWidget {
  const TeleprompterView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ReaderProvider>(
      builder: (context, provider, child) {
        if (provider.isParsing) {
          return const Center(
            child: Text(
              "🧩 正在连接神经数据链路...",
              style: TextStyle(
                color: Colors.white30,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }

        if (provider.sentences.isEmpty) {
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

        final String text = provider.currentSentence ?? "";

        return Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.visible,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        );
      },
    );
  }
}
