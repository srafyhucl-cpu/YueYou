import 'package:flutter/material.dart';
import 'dart:math' as math;

/// 棋盘重置翻转动画包装器
/// 当重置游戏时触发 3D 翻转效果
class BoardResetAnimation extends StatefulWidget {
  final Widget child;
  final bool triggerReset;

  const BoardResetAnimation({
    super.key,
    required this.child,
    required this.triggerReset,
  });

  @override
  State<BoardResetAnimation> createState() => _BoardResetAnimationState();
}

class _BoardResetAnimationState extends State<BoardResetAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;
  late Animation<double> _fadeAnimation;
  bool _previousTrigger = false;

  @override
  void initState() {
    super.initState();
    _previousTrigger = widget.triggerReset;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: math.pi,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    ),);

    _fadeAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        weight: 50,
      ),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(BoardResetAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 检测重置触发
    if (widget.triggerReset != _previousTrigger && widget.triggerReset) {
      _controller.forward(from: 0.0);
    }
    _previousTrigger = widget.triggerReset;
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
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(_rotationAnimation.value),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: widget.child,
          ),
        );
      },
    );
  }
}
