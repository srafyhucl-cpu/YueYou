import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/core/utils/cyber_performance_detector.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';

/// 赛博朋克风格全局弹窗封装
/// 替代 Navigator.push 全屏跳转，点击外部可关闭
Future<T?> showCyberModal<T>({
  required BuildContext context,
  required Widget child,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: CyberColors.blackOverlay,
    transitionDuration: CyberDimensions.animNormal,
    pageBuilder: (context, animation, secondaryAnimation) {
      return SafeArea(
        child: Center(
          child: Material(
            type: MaterialType.transparency,
            child: ScaleTransition(
              scale: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: FadeTransition(
                opacity: animation,
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: CyberDimensions.spacingXL,
                    vertical: CyberDimensions.spacingXL * 2,
                  ),
                  constraints: BoxConstraints(
                    maxWidth: 500,
                    maxHeight: MediaQuery.of(context).size.height * 0.85,
                  ),
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(CyberDimensions.radiusL),
                    border: Border.all(
                      color: CyberColors.neonCyan.withValues(alpha: 0.4),
                      width: CyberDimensions.borderThick,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: CyberColors.neonCyan.withValues(alpha: 0.25),
                        blurRadius: CyberDimensions.shadowBlurModalGlow,
                        spreadRadius: 2,
                      ),
                      const BoxShadow(
                        color: CyberColors.blackShadow,
                        blurRadius: CyberDimensions.shadowBlurModalDrop,
                        offset: Offset(0, 15),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      CyberDimensions.radiusL - CyberDimensions.borderThick,
                    ),
                    child: ProviderScope.containerOf(context)
                                .read(settingsProvider)
                                .currentAnimationLevel ==
                            CyberAnimationLevel.low
                        ? Container(
                            color:
                                CyberColors.glassDark.withValues(alpha: 0.98),
                            child: child, // 🚨 直接渲染内容
                          )
                        : BackdropFilter(
                            filter: ImageFilter.blur(
                              sigmaX: CyberDimensions.blurStrong,
                              sigmaY: CyberDimensions.blurStrong,
                            ),
                            child: Container(
                              color: CyberColors.glassDark,
                              child: child, // 🚨 移除了冗余的内部 ClipRRect，统一在外层精准截断
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
