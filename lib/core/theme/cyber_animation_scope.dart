import 'package:flutter/widgets.dart';

import 'package:yueyou/core/utils/cyber_performance_detector.dart';

/// 向共享 UI 提供当前动画等级，不暴露具体设置 Provider。
class CyberAnimationScope extends InheritedWidget {
  final CyberAnimationLevel animationLevel;

  const CyberAnimationScope({
    super.key,
    required this.animationLevel,
    required super.child,
  });

  static CyberAnimationLevel of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<CyberAnimationScope>()
            ?.animationLevel ??
        CyberAnimationLevel.high;
  }

  @override
  bool updateShouldNotify(CyberAnimationScope oldWidget) {
    return oldWidget.animationLevel != animationLevel;
  }
}
