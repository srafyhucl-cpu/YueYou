import 'package:flutter/material.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/utils/safe_area_utils.dart';

/// 顶部安全区包裹组件
/// 严格执行“呼吸感”准则：SafeArea + 额外 24.0px 的 Padding
class SafePaddingWrap extends StatelessWidget {
  final Widget child;

  const SafePaddingWrap({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CyberColors.background,
      child: SafeArea(
        bottom: false, // 顶部组件不强制底部安全区
        child: Padding(
          padding: const EdgeInsets.only(
            top: SafeAreaUtils.topBreathPadding,
            left: 16.0,
            right: 16.0,
          ),
          child: child,
        ),
      ),
    );
  }
}
