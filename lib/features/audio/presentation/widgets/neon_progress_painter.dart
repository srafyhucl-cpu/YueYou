import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';

/// 灵动岛霓虹进度条绘制器
/// 从顶部中心开始，顺时针绘制进度，带呼吸光晕效果
///
/// P0-A 性能优化：
/// - 4 个 Paint 实例复用（静态可变），仅在 paint() 内修改动态属性
/// - LinearGradient shader 按 (size, color) 缓存，不再每帧 createShader
/// - 中层光晕 MaskFilter 使用 const（固定值不随呼吸变化）
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

  // ── P0-A：复用 Paint 实例，避免每帧分配 ──
  static final Paint _outerGlowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  static final Paint _middleGlowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

  static final Paint _progressPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  static final Paint _pulsePaint = Paint()..style = PaintingStyle.fill;

  // ── P0-A：LinearGradient shader 缓存，按 (size, color) key ──
  static Size? _cachedShaderSize;
  static Color? _cachedShaderColor;
  static Shader? _cachedShader;

  Shader _getShader(Rect rect) {
    if (_cachedShader != null &&
        _cachedShaderSize!.width == rect.width &&
        _cachedShaderSize!.height == rect.height &&
        _cachedShaderColor == color) {
      return _cachedShader!;
    }
    _cachedShader = LinearGradient(
      colors: [
        color,
        color.withValues(alpha: 0.8),
        color,
      ],
      stops: const [0.0, 0.5, 1.0],
    ).createShader(rect);
    _cachedShaderSize = rect.size;
    _cachedShaderColor = color;
    return _cachedShader!;
  }

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

    // 外层光晕（呼吸效果）—— 仅修改动态属性
    _outerGlowPaint
      ..color = color.withValues(alpha: 0.15 * breathIntensity)
      ..strokeWidth = strokeWidth + 8
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * breathIntensity);

    // 中层光晕 —— maskFilter 已是 const，仅更新颜色和宽度
    _middleGlowPaint
      ..color = color.withValues(alpha: 0.3 * breathIntensity)
      ..strokeWidth = strokeWidth + 4;

    // 主进度条（渐变色）—— shader 走缓存
    _progressPaint
      ..shader = _getShader(rect)
      ..strokeWidth = strokeWidth;

    // 绘制层次：外层光晕 -> 中层光晕 -> 主进度条
    canvas.drawPath(progressPath, _outerGlowPaint);
    canvas.drawPath(progressPath, _middleGlowPaint);
    canvas.drawPath(progressPath, _progressPaint);

    // 进度条头部高亮点（脉冲效果）
    if (progress > 0.01) {
      final headPoint = pathMetrics.getTangentForOffset(endOffset)?.position;
      if (headPoint != null) {
        final pulseSize = 3.0 + 2.0 * breathIntensity;
        _pulsePaint
          ..color = color
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, pulseSize);
        canvas.drawCircle(headPoint, pulseSize, _pulsePaint);
      }
    }
  }

  @override
  bool shouldRepaint(NeonProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.animationValue != animationValue;
  }
}
