import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rive/rive.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';
import 'package:yueyou/features/companion/domain/xiaoyo_semantics.dart';
import 'package:yueyou/features/companion/domain/xiaoyo_triggers.dart';
import 'package:yueyou/features/companion/presentation/rive_state_machine_input_sink.dart';
import 'package:yueyou/features/companion/presentation/xiaoyo_rive_input_adapter.dart';

/// Xiaoyo 角色容器，负责资源生命周期与静态降级，不承载业务状态。
class XiaoyoMascot extends StatefulWidget {
  final XiaoyoSemantics semantics;
  final bool enableRive;
  final String assetPath;
  final double width;
  final double height;
  final VoidCallback? onTap;

  const XiaoyoMascot({
    super.key,
    this.semantics = const XiaoyoSemantics(),
    this.enableRive = false,
    this.assetPath = 'assets/rive/xiaoyo.riv',
    this.width = CyberDimensions.companionMascotWidth,
    this.height = CyberDimensions.companionMascotHeight,
    this.onTap,
  });

  @override
  State<XiaoyoMascot> createState() => _XiaoyoMascotState();
}

class _XiaoyoMascotState extends State<XiaoyoMascot> {
  Artboard? _artboard;
  StateMachineController? _controller;
  XiaoyoRiveInputAdapter? _adapter;

  @override
  void initState() {
    super.initState();
    if (widget.enableRive) _loadRive();
  }

  @override
  void didUpdateWidget(covariant XiaoyoMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enableRive &&
        (!oldWidget.enableRive || widget.assetPath != oldWidget.assetPath)) {
      _disposeRive();
      _loadRive();
    } else if (!widget.enableRive && oldWidget.enableRive) {
      _disposeRive();
    }
    _adapter?.apply(widget.semantics);
  }

  Future<void> _loadRive() async {
    try {
      final data = await rootBundle.load(widget.assetPath);
      final file = RiveFile.import(data);
      final artboard = file.mainArtboard;
      final controller = StateMachineController.fromArtboard(
        artboard,
        'XiaoyoStateMachine',
      );
      if (controller == null) {
        throw StateError('XiaoyoStateMachine 状态机未找到');
      }
      artboard.addController(controller);
      final adapter = XiaoyoRiveInputAdapter(
        sink: RiveStateMachineInputSink(controller),
        onMissingInput: (inputName) {
          CyberLogger.captureWarning(
            StateError('Xiaoyo Rive 输入未找到'),
            tag: 'dashboard',
            extra: {'input': inputName},
          );
        },
      )..apply(widget.semantics);
      if (!mounted || !widget.enableRive) {
        controller.dispose();
        return;
      }
      _disposeRive();
      setState(() {
        _artboard = artboard;
        _controller = controller;
        _adapter = adapter;
      });
    } catch (error, stackTrace) {
      CyberLogger.captureWarning(
        error,
        stack: stackTrace,
        tag: 'dashboard',
        extra: {'context': 'Xiaoyo Rive 资源回退'},
      );
      if (mounted) setState(() => _artboard = null);
    }
  }

  void _disposeRive() {
    _controller?.dispose();
    _controller = null;
    _adapter = null;
    _artboard = null;
  }

  @override
  void dispose() {
    _disposeRive();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = _artboard == null || !widget.enableRive
        ? XiaoyoStaticFallback(
            width: widget.width,
            height: widget.height,
            semantics: widget.semantics,
          )
        : Rive(artboard: _artboard!, fit: BoxFit.contain);
    return Semantics(
      button: widget.onTap != null,
      label: 'Xiaoyo',
      child: GestureDetector(
        onTap: () {
          _adapter?.fire(XiaoyoTrigger.tap);
          widget.onTap?.call();
        },
        child:
            SizedBox(width: widget.width, height: widget.height, child: child),
      ),
    );
  }
}

/// Rive 不可用时的轻量静态角色，保证入口和状态反馈仍然可见。
class XiaoyoStaticFallback extends StatelessWidget {
  final double width;
  final double height;
  final XiaoyoSemantics semantics;

  const XiaoyoStaticFallback({
    super.key,
    required this.width,
    required this.height,
    this.semantics = const XiaoyoSemantics(),
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _XiaoyoFallbackPainter(semantics: semantics),
        size: Size(width, height),
      ),
    );
  }
}

class _XiaoyoFallbackPainter extends CustomPainter {
  final XiaoyoSemantics semantics;

  const _XiaoyoFallbackPainter({required this.semantics});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.42);
    final radius = size.shortestSide * 0.22;
    final color = semantics.audioState == XiaoyoAudioState.error
        ? CyberColors.neonPink
        : CyberColors.neonCyan;
    final glow = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16.0);
    canvas.drawCircle(center, radius + 10.0, glow);

    final core = Paint()
      ..color = CyberColors.surface
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, core);
    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = CyberDimensions.borderThick;
    canvas.drawCircle(center, radius, outline);

    final eyePaint = Paint()..color = color;
    final eyeOffset = Offset(
      semantics.lookX.clamp(-1.0, 1.0).toDouble() * radius * 0.16,
      semantics.lookY.clamp(-1.0, 1.0).toDouble() * radius * 0.16,
    );
    for (final side in <double>[-0.5, 0.5]) {
      canvas.drawCircle(
        center + Offset(side * radius, -radius * 0.12) + eyeOffset,
        radius * 0.1,
        eyePaint,
      );
    }

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = CyberDimensions.borderNormal
      ..strokeCap = StrokeCap.round;
    final mouth = Path()
      ..moveTo(center.dx - radius * 0.3, center.dy + radius * 0.3)
      ..quadraticBezierTo(
        center.dx,
        center.dy + radius * (0.3 + semantics.energy * 0.15),
        center.dx + radius * 0.3,
        center.dy + radius * 0.3,
      );
    canvas.drawPath(mouth, linePaint);
  }

  @override
  bool shouldRepaint(_XiaoyoFallbackPainter oldDelegate) =>
      oldDelegate.semantics != semantics;
}
