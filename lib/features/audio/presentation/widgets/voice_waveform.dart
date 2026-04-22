import 'dart:math';
import 'package:flutter/material.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';

/// 声纹跳动动画组件
/// 用于灵动岛内部，当 TTS 播报时显示动态声纹
class VoiceWaveform extends StatefulWidget {
  final bool isActive;
  final Color color;

  const VoiceWaveform({
    super.key,
    required this.isActive,
    this.color = CyberColors.neonCyan,
  });

  @override
  State<VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<VoiceWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Random _random = Random();
  final List<double> _heights = [0.3, 0.5, 0.7, 0.5, 0.3];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(5, (index) {
            final baseHeight = _heights[index];
            final height = widget.isActive
                ? baseHeight + _random.nextDouble() * 0.4
                : 0.15;
            return Container(
              width: 2.5,
              height: 16 * height,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: widget.color.withOpacity(widget.isActive ? 0.9 : 0.3),
                borderRadius: BorderRadius.circular(CyberDimensions.radiusXS),
              ),
            );
          }),
        );
      },
    );
  }
}
