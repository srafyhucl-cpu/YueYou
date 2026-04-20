import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/cyber_colors.dart';
import '../../../core/theme/cyber_dimensions.dart';
import '../../../core/theme/cyber_text_styles.dart';

enum ToastType {
  info,
  error,
  success,
}

class CyberToast {
  static OverlayEntry? _currentEntry;
  static Timer? _currentTimer;

  static void show(
    BuildContext context,
    String message,
    {ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 2, milliseconds: 500)}
  ) {
    // 移除之前的 Toast
    _removeCurrentEntry();

    // 创建新的 OverlayEntry
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (context) => _CyberToastWidget(
        message: message,
        type: type,
        onRemove: () => _currentEntry = null,
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);

    // 设置定时器，自动移除
    _currentTimer?.cancel();
    _currentTimer = Timer(duration, () {
      _removeCurrentEntry();
    });
  }

  static void _removeCurrentEntry() {
    if (_currentEntry != null) {
      _currentEntry?.remove();
      _currentEntry = null;
    }
    _currentTimer?.cancel();
    _currentTimer = null;
  }
}

class _CyberToastWidget extends StatefulWidget {
  final String message;
  final ToastType type;
  final VoidCallback onRemove;

  const _CyberToastWidget({
    required this.message,
    required this.type,
    required this.onRemove,
  });

  @override
  __CyberToastWidgetState createState() => __CyberToastWidgetState();
}

class __CyberToastWidgetState extends State<_CyberToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getBorderColor() {
    switch (widget.type) {
      case ToastType.error:
        return CyberColors.neonPink;
      case ToastType.success:
        return CyberColors.neonGreen;
      case ToastType.info:
      default:
        return CyberColors.neonCyan;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 40,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: CyberDimensions.spacingML),
              padding: const EdgeInsets.symmetric(horizontal: CyberDimensions.spacingM, vertical: CyberDimensions.spacingMS),
              decoration: BoxDecoration(
                color: CyberColors.glassDark,
                borderRadius: BorderRadius.circular(CyberDimensions.radiusS),
                border: Border.all(
                  color: _getBorderColor(),
                  width: CyberDimensions.borderNormal,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _getBorderColor().withOpacity(0.5),
                    blurRadius: CyberDimensions.blurLight,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Text(
                widget.message,
                style: CyberTextStyles.teleprompterActive,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
