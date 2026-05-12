import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';

/// 合并粒子效果组件
/// 消消乐风格：径向扩散的小光点 + 渐隐动画
class MergeParticle extends StatefulWidget {
  final Color color;
  final VoidCallback? onComplete;

  const MergeParticle({
    super.key,
    required this.color,
    this.onComplete,
  });

  @override
  State<MergeParticle> createState() => _MergeParticleState();
}

class _MergeParticleState extends State<MergeParticle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: CyberDimensions.animMedium,
      vsync: this,
    );

    // 生成 8 个粒子，均匀分布在圆周上
    _particles = List.generate(8, (i) {
      final angle = (i * math.pi * 2) / 8;
      return _Particle(
        angle: angle,
        distance: 40.0, // 最终飘散距离
        size: 6.0 + math.Random().nextDouble() * 6.0, // 6-10px
      );
    });

    _controller.forward().then((_) {
      widget.onComplete?.call();
    });
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
        return CustomPaint(
          painter: _ParticlePainter(
            particles: _particles,
            progress: _controller.value,
            color: widget.color,
          ),
          size: const Size(100, 100),
        );
      },
    );
  }
}

class _Particle {
  final double angle;
  final double distance;
  final double size;

  _Particle({
    required this.angle,
    required this.distance,
    required this.size,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;
  final Color color;

  // P2-1：复用 Paint 实例，消除每帧 16 个 Paint 分配
  static final Paint _corePaint = Paint();
  static final Paint _glowPaint = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

  _ParticlePainter({
    required this.particles,
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // 缓动曲线：快速启动 + 减速
    final easedProgress = Curves.easeOut.transform(progress);
    // 透明度：1.0 → 0.0
    final opacity = (1.0 - progress).clamp(0.0, 1.0);

    _corePaint.color = color.withValues(alpha: opacity * 0.8);
    _glowPaint.color = color.withValues(alpha: opacity * 0.3);

    for (final particle in particles) {
      // 计算粒子当前位置
      final currentDistance = particle.distance * easedProgress;
      final pos = Offset(
        center.dx + math.cos(particle.angle) * currentDistance,
        center.dy + math.sin(particle.angle) * currentDistance,
      );
      final shrink = 1.0 - progress * 0.3;

      // 绘制圆形光点
      canvas.drawCircle(pos, particle.size * shrink, _corePaint);

      // 外层光晕
      canvas.drawCircle(pos, particle.size * 1.5 * shrink, _glowPaint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
