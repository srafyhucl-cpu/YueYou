import 'package:flutter/material.dart';
import 'package:yueyou/features/audio/presentation/widgets/cyber_player_console.dart';

/// 跨一级导航页签保留的播放控制插槽。
///
/// 播放状态和控制行为仍由既有 [CyberPlayerConsole] 负责，壳层不创建第二套
/// TTS 会话，也不直接操作 ReaderProvider 或 TtsAudioNotifier。
class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(child: CyberPlayerConsole());
  }
}
