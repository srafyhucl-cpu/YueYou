import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui';
import '../../../core/theme/cyber_colors.dart';
import '../../../core/theme/cyber_dimensions.dart';
import '../../../core/theme/cyber_text_styles.dart';
import '../../../features/game_2048/presentation/widgets/board_mascot.dart';
import '../../../main.dart';

enum ToastType {
  info,
  error,
  success,
}

class CyberToast {
  static OverlayEntry? _currentEntry;
  static Timer? _currentTimer;

  static void show(
    String message,
    {ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 2, milliseconds: 500)}
  ) {
    // 移除之前的 Toast
    _removeCurrentEntry();

    // 创建新的 OverlayEntry
    final overlay = globalNavigatorKey.currentState?.overlay;
    if (overlay == null) return;
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
        return CyberColors.neonCyan;
    }
  }

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
                margin: const EdgeInsets.symmetric(horizontal: CyberDimensions.spacingML),
                decoration: BoxDecoration(
                  color: CyberColors.glassDark,
                  borderRadius: BorderRadius.circular(CyberDimensions.radiusL),
                  border: Border.all(
                    color: _getBorderColor(),
                    width: CyberDimensions.borderThick,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _getBorderColor().withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(CyberDimensions.radiusL),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // XIAOYO Avatar PFP
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: CyberColors.background.withValues(alpha: 0.8),
                                border: Border.all(
                                  color: _getBorderColor().withValues(alpha: 0.7),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _getBorderColor().withValues(alpha: 0.5),
                                    blurRadius: 8,
                                  )
                                ],
                              ),
                              child: ClipOval(
                                child: Transform.scale(
                                  scale: 0.65,
                                  // Transform.translate 去微调位置以确保脸部在圆圈正中心
                                  child: Transform.translate(
                                    offset: const Offset(0, -5),
                                    child: const IgnorePointer(
                                      child: BoardMascot(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            // Text Section
                            Flexible(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'XIAOYO SYSTEM',
                                    style: CyberTextStyles.captionBold.copyWith(
                                      color: _getBorderColor(),
                                      fontSize: 10,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
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
}
