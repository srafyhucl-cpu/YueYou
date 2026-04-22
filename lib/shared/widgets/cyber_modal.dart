import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';

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
    transitionDuration: const Duration(milliseconds: 300),
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
                      horizontal: CyberDimensions.spacingXL, vertical: 64),
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
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                      const BoxShadow(
                        color: CyberColors.blackShadow,
                        blurRadius: 40,
                        offset: Offset(0, 15),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(CyberDimensions.radiusL),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                          sigmaX: CyberDimensions.blurStrong,
                          sigmaY: CyberDimensions.blurStrong),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: CyberColors.glassDark,
                        ),
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(CyberDimensions.radiusL),
                          child: child, // 🚨 极其重要：双重防溢出保护
                        ),
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
