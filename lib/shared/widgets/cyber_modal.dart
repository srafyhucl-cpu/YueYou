import 'dart:ui';
import 'package:flutter/material.dart';

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
    barrierColor: Colors.black.withOpacity(0.7),
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
                  margin:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
                  constraints: BoxConstraints(
                    maxWidth: 500,
                    maxHeight: MediaQuery.of(context).size.height * 0.85,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFF22D3EE).withOpacity(0.4),
                      width: 2.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF22D3EE).withOpacity(0.25),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                      const BoxShadow(
                        color: Color.fromRGBO(0, 0, 0, 0.6),
                        blurRadius: 40,
                        offset: Offset(0, 15),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Color(0xE60A0A0F),
                        ),
                        child: child,
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
