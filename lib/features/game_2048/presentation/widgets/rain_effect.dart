import 'dart:math';
import 'package:flutter/material.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';

/// 赛博朋克风格下雨特效
/// 用于 Game Over 弹窗，营造失败时的氛围感
class RainEffect extends StatefulWidget {
  final int rainCount;

  const RainEffect({
    super.key,
    this.rainCount = 20,
  });

  @override
  State<RainEffect> createState() => _RainEffectState();
}

class _RainEffectState extends State<RainEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_RainDrop> _rainDrops = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();

    // 初始化雨滴
    // 让每个雨滴有不同的初始进度，实现连续下雨效果
    for (int i = 0; i < widget.rainCount; i++) {
      _rainDrops.add(
        _RainDrop(
          xOffset: _random.nextDouble(),
          initialProgress: i / widget.rainCount, // 初始进度错开
          speed: 0.8 + _random.nextDouble() * 0.4, // 0.8-1.2
          opacity: 0.3 + _random.nextDouble() * 0.3,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(CyberDimensions.radiusM),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _RainPainter(
              rainDrops: _rainDrops,
              progress: _controller.value,
            ),
          );
        },
      ),
    );
  }
}

/// 雨滴数据模型
class _RainDrop {
  final double xOffset; // 水平位置比例 (0-1)
  final double initialProgress; // 初始进度偏移 (0-1)
  final double speed; // 速度倍数
  final double opacity; // 透明度

  _RainDrop({
    required this.xOffset,
    required this.initialProgress,
    required this.speed,
    required this.opacity,
  });
}

/// 雨滴绘制器
class _RainPainter extends CustomPainter {
  final List<_RainDrop> rainDrops;
  final double progress;

  // 雨滴固定参数
  static const double dropLength = 15.0;
  static const double dropWidth = 1.5;

  _RainPainter({
    required this.rainDrops,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final drop in rainDrops) {
      // 计算当前雨滴进度（每个雨滴独立循环）
      final double currentProgress =
          (progress * drop.speed + drop.initialProgress) % 1.0;

      // 计算雨滴位置（从顶部流到底部）
      final x = drop.xOffset * size.width;
      final totalDistance = size.height + dropLength;
      final yStart = currentProgress * totalDistance - dropLength;
      final yEnd = yStart + dropLength;

      // 只绘制在可见区域内的雨滴
      if (yEnd < 0 || yStart > size.height) continue;

      // 计算淡入淡出效果
      // 前15%进度淡入，后15%进度淡出
      double fadeMultiplier = 1.0;
      if (currentProgress < 0.15) {
        fadeMultiplier = currentProgress / 0.15; // 0-1 淡入
      } else if (currentProgress > 0.85) {
        fadeMultiplier = (1.0 - currentProgress) / 0.15; // 1-0 淡出
      }

      // 绘制雨滴（简单线条 + 渐变 + 淡入淡出）
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            CyberColors.neonCyan
                .withValues(alpha: drop.opacity * 0.2 * fadeMultiplier),
            CyberColors.neonCyan
                .withValues(alpha: drop.opacity * 0.8 * fadeMultiplier),
          ],
        ).createShader(Rect.fromLTRB(x - 1, yStart, x + 1, yEnd))
        ..strokeWidth = dropWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(x, yStart),
        Offset(x, yEnd),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RainPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
