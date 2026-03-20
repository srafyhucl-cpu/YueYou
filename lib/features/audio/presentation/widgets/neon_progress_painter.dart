import 'package:flutter/material.dart';

/// 霓虹环形进度条绘制器
/// 沿着 StadiumBorder 胶囊形状绘制进度线
class NeonProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  NeonProgressPainter({
    required this.progress,
    this.color = const Color(0xFF22D3EE),
    this.strokeWidth = 2.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final radius = size.height / 2;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));

    final pathMetrics = path.computeMetrics().first;
    final totalLength = pathMetrics.length;
    final progressLength = totalLength * progress.clamp(0.0, 1.0);

    final progressPath = pathMetrics.extractPath(0, progressLength);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = color.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawPath(progressPath, glowPaint);
    canvas.drawPath(progressPath, paint);
  }

  @override
  bool shouldRepaint(NeonProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
