import 'package:flutter/material.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';

/// 漂浮加分特效组件
/// 当产生合并得分时，显示 +Score 的赛博字体，带有向上漂浮并淡出的动画
class FloatingScore extends StatefulWidget {
  final int score;
  final Offset position;
  final VoidCallback onComplete;

  const FloatingScore({
    super.key,
    required this.score,
    required this.position,
    required this.onComplete,
  });

  @override
  State<FloatingScore> createState() => _FloatingScoreState();
}

class _FloatingScoreState extends State<FloatingScore>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _offsetAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // 向上漂浮动画
    _offsetAnimation = Tween<double>(begin: 0, end: -80).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    // 淡出动画
    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
      ),
    );

    _controller.forward().then((_) => widget.onComplete());
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
        return Positioned(
          left: widget.position.dx,
          top: widget.position.dy + _offsetAnimation.value,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: CyberDimensions.spacingMS,
                vertical: CyberDimensions.spacingS - CyberDimensions.spacingXXS,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    CyberColors.neonPink.withOpacity(0.8),
                    CyberColors.neonPurple.withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(CyberDimensions.radiusS),
                boxShadow: [
                  BoxShadow(
                    color: CyberColors.pinkGlow.withOpacity(0.6),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Text(
                '+${widget.score}',
                style: CyberTextStyles.gameGridNumber.copyWith(
                  color: CyberColors.whiteHigh,
                  fontSize: 20,
                  fontFamily: CyberTextStyles.monoFont,
                  shadows: const [
                    Shadow(
                      color: CyberColors.blackDim,
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
