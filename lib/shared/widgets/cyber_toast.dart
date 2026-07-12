import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:yueyou/core/theme/cyber_animation_scope.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/core/theme/cyber_text_styles.dart';
import 'package:yueyou/core/utils/cyber_performance_detector.dart';

enum ToastType {
  info,
  error,
  success,
}

typedef CyberToastShowOverride = void Function(
  String message,
  BuildContext context,
  ToastType type,
);

class CyberToast {
  static OverlayEntry? _currentEntry;
  static Timer? _currentTimer;
  static bool _autoDismissEnabled = true;
  // P2-1：去重 + 滑动续期所需的"当前 Toast"标识。
  // 同一消息在短时间内重复触发时，只续期不重建，避免连续闪烁。
  static String? _currentMessage;
  static ToastType? _currentType;
  static CyberToastShowOverride? _showOverrideForTesting;

  /// 测试专用替身：允许监听器测试验证调用编排而不创建真实 Overlay。
  @visibleForTesting
  static void setShowOverrideForTesting(CyberToastShowOverride? override) {
    _showOverrideForTesting = override;
  }

  /// 测试结束时清理静态 Overlay 与计时器，避免跨用例残留。
  static void resetForTesting() {
    _autoDismissEnabled = true;
    _showOverrideForTesting = null;
    _removeCurrentEntry();
  }

  /// 测试专用：关闭自动消失计时器，避免 fake async 测试跨树残留。
  static void setAutoDismissForTesting(bool enabled) {
    _autoDismissEnabled = enabled;
    if (!enabled) _currentTimer?.cancel();
  }

  static void show(
    String message, {
    required BuildContext context,
    ToastType type = ToastType.info,
    Duration duration = CyberDimensions.toastDuration,
  }) {
    final override = _showOverrideForTesting;
    if (override != null) {
      override(message, context, type);
      return;
    }

    // P2-1：相同 message + type 的连续触发只刷新计时器，
    // 避免 OverlayEntry 反复 remove/insert 引发动画闪烁与无谓重建。
    if (_currentEntry != null &&
        _currentMessage == message &&
        _currentType == type) {
      if (_autoDismissEnabled) {
        _currentTimer?.cancel();
        _currentTimer = Timer(duration, _removeCurrentEntry);
      }
      return;
    }

    // 不同消息：移除旧 Toast，创建新 OverlayEntry
    _removeCurrentEntry();

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final entry = OverlayEntry(
      builder: (context) => _CyberToastWidget(message: message, type: type),
    );

    _currentEntry = entry;
    _currentMessage = message;
    _currentType = type;
    overlay.insert(entry);

    // 自动移除定时器
    if (_autoDismissEnabled) {
      _currentTimer = Timer(duration, _removeCurrentEntry);
    }
  }

  static void _removeCurrentEntry() {
    if (_currentEntry != null) {
      _currentEntry?.remove();
      _currentEntry = null;
    }
    _currentTimer?.cancel();
    _currentTimer = null;
    _currentMessage = null;
    _currentType = null;
  }
}

class _CyberToastWidget extends StatefulWidget {
  final String message;
  final ToastType type;

  const _CyberToastWidget({
    required this.message,
    required this.type,
  });

  @override
  _CyberToastWidgetState createState() => _CyberToastWidgetState();
}

class _CyberToastWidgetState extends State<_CyberToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late CurvedAnimation _slideCurve;
  late CurvedAnimation _fadeCurve;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: CyberDimensions.animNormal,
      vsync: this,
    );

    _slideCurve = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(_slideCurve);

    _fadeCurve = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_fadeCurve);

    _controller.forward();
  }

  @override
  void dispose() {
    _slideCurve.dispose();
    _fadeCurve.dispose();
    _controller.dispose();
    super.dispose();
  }

  Color _getBorderColor() => switch (widget.type) {
        ToastType.error => CyberColors.neonPink,
        ToastType.success => CyberColors.neonGreen,
        ToastType.info => CyberColors.neonCyan
      };

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + CyberDimensions.spacingM,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Align(
            alignment: Alignment.topCenter,
            child: IntrinsicWidth(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.85,
                ),
                margin: const EdgeInsets.symmetric(
                  horizontal: CyberDimensions.spacingML,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(CyberDimensions.radiusL),
                  border: Border.all(
                    color: _getBorderColor(),
                    width: CyberDimensions.borderThick,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _getBorderColor().withValues(alpha: 0.3),
                      blurRadius: CyberDimensions.spacingM,
                      offset: const Offset(0, CyberDimensions.spacingXS),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    CyberDimensions.radiusL - CyberDimensions.borderThick,
                  ),
                  child: CyberAnimationScope.of(context) ==
                          CyberAnimationLevel.low
                      ? Container(
                          color: CyberColors.glassDark.withValues(alpha: 0.98),
                          child: _buildContent(),
                        )
                      : BackdropFilter(
                          filter: ImageFilter.blur(
                            sigmaX: CyberDimensions.blurLight,
                            sigmaY: CyberDimensions.blurLight,
                          ),
                          child: Container(
                            color: CyberColors.glassDark,
                            child: _buildContent(),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CyberDimensions.spacingM,
        vertical: CyberDimensions.spacingMS,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CyberColors.background.withValues(alpha: 0.8),
              border: Border.all(
                color: _getBorderColor().withValues(alpha: 0.7),
                width: CyberDimensions.borderNormal,
              ),
              boxShadow: [
                BoxShadow(
                  color: _getBorderColor().withValues(alpha: 0.5),
                  blurRadius: CyberDimensions.glowBlurRadius,
                ),
              ],
            ),
            child: Icon(
              Icons.auto_awesome,
              color: _getBorderColor(),
              size: 24,
            ),
          ),
          const SizedBox(
            width: CyberDimensions.spacingMS + CyberDimensions.spacingXXS,
          ),
          // Text Section
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'XIAOYO',
                  style: CyberTextStyles.captionBold.copyWith(
                    color: _getBorderColor(),
                    fontSize: 10,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: CyberDimensions.spacingXS),
                Text(
                  widget.message,
                  style: CyberTextStyles.bodySmallBold.copyWith(
                    color: CyberColors.whiteHigh,
                    height: 1.3,
                  ),
                  softWrap: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
