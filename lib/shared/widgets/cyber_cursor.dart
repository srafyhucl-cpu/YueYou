import 'package:flutter/material.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';

/// 赛博朋克风格闪烁光标
/// 实现类似经典终端的实心矩形块，带呼吸闪烁动画与霓虹发光
class CyberCursor extends StatefulWidget {
  final double width;
  final double height;

  const CyberCursor({
    super.key,
    this.width = 12.0,
    this.height = 24.0,
  });

  @override
  State<CyberCursor> createState() => _CyberCursorState();
}

class _CyberCursorState extends State<CyberCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // 呼吸感：从 0.2 到 1.0 的平滑循环
    _opacityAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacityAnimation,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: const BoxDecoration(
          color: CyberColors.neonGreen,
          // 赛博霓虹发光阴影
          boxShadow: [
            BoxShadow(
              color: CyberColors.glowShadow,
              blurRadius: 8.0,
              spreadRadius: 1.0,
            ),
          ],
        ),
      ),
    );
  }
}
