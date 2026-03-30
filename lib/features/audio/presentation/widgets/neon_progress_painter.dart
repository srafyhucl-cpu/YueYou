import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';

/// 灵动岛霓虹进度条绘制器
/// 从顶部中心开始，顺时针绘制进度，带呼吸光晕效果
class NeonProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;
  final double animationValue; // 呼吸动画值 0.0 ~ 1.0

  NeonProgressPainter({
    required this.progress,
    this.color = CyberColors.neonCyan,
    this.strokeWidth = 2.5,
    this.animationValue = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final radius = size.height / 2;

    // 创建胶囊路径
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));

    final pathMetrics = path.computeMetrics().first;
    final totalLength = pathMetrics.length;

    // 计算顶部中心点的起始位置
    // 胶囊路径从左上角开始，需要偏移到顶部中心
    final topCenterOffset = size.width / 2; // 顶部中心距离起点的距离

    // 从顶部中心开始，顺时针绘制进度
    final progressLength = totalLength * progress.clamp(0.0, 1.0);
    final startOffset = topCenterOffset;
    final endOffset = (startOffset + progressLength) % totalLength;

    Path progressPath;
    if (endOffset >= startOffset) {
      // 进度未跨越起点
      progressPath = pathMetrics.extractPath(startOffset, endOffset);
    } else {
      // 进度跨越起点，需要分两段绘制
      final path1 = pathMetrics.extractPath(startOffset, totalLength);
      final path2 = pathMetrics.extractPath(0, endOffset);
      progressPath = Path()
        ..addPath(path1, Offset.zero)
        ..addPath(path2, Offset.zero);
    }

    // 呼吸效果：光晕强度随动画值变化
    final breathIntensity = 0.7 + 0.3 * math.sin(animationValue * math.pi * 2);

    // 外层光晕（呼吸效果）
    final outerGlowPaint = Paint()
      ..color = color.withOpacity(0.15 * breathIntensity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 8
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * breathIntensity);

    // 中层光晕
    final middleGlowPaint = Paint()
      ..color = color.withOpacity(0.3 * breathIntensity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 4
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    // 主进度条（渐变色）
    final progressPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          color,
          color.withOpacity(0.8),
          color,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // 绘制层次：外层光晕 -> 中层光晕 -> 主进度条
    canvas.drawPath(progressPath, outerGlowPaint);
    canvas.drawPath(progressPath, middleGlowPaint);
    canvas.drawPath(progressPath, progressPaint);

    // 进度条头部高亮点（脉冲效果）
    if (progress > 0.01) {
      final headPoint = pathMetrics.getTangentForOffset(endOffset)?.position;
      if (headPoint != null) {
        final pulseSize = 3.0 + 2.0 * breathIntensity;
        final pulsePaint = Paint()
          ..color = color
          ..style = PaintingStyle.fill
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, pulseSize);

        canvas.drawCircle(headPoint, pulseSize, pulsePaint);
      }
    }
  }

  @override
  bool shouldRepaint(NeonProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.animationValue != animationValue;
  }
}
