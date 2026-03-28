import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yueyou/features/game_2048/providers/game_provider.dart';

/// 棋盘吉祥物 —— 趴在棋盘上方，眼球跟随玩家滑动方向
/// 合成大棋子时欢呼跳跃，失败时陪你一起难过
class BoardMascot extends StatefulWidget {
  const BoardMascot({super.key});

  @override
  State<BoardMascot> createState() => _BoardMascotState();
}

class _BoardMascotState extends State<BoardMascot>
    with TickerProviderStateMixin {
  // ── 眼球方向层（可随时打断，从当前值插值，绝不跳变）──
  late AnimationController _eyeController;
  late Animation<Offset> _eyeAnimation;

  // ── 身体跳跃层（欢呼时可重启，不排队）──
  late AnimationController _bodyController;
  late Animation<double> _bodyAnimation;

  // ── 表情层（-1=难过, 0=正常, 1=开心）──
  late AnimationController _expressionController;
  late Animation<double> _expressionAnimation;

  // ── 空闲浮动层（±3px 正弦往返，让她像活着一样）──
  late AnimationController _idleController;
  late Animation<double> _idleAnimation;

  // ── 头部倾斜（复用 _eyeController 同步，左右滑动各 ±6°）──
  late Animation<double> _tiltAnimation;

  // ── 跟随棋盘掀起的晃动（每次滑动触发，爬墙头感）──
  late AnimationController _wobbleController;
  late Animation<Offset> _wobbleAnimation;

  // ── 眨眼层（独立随机循环，与其他层完全解耦）──
  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;

  // ── GameProvider 监听 ──
  GameProvider? _watchedProvider;
  Direction? _lastDirection;
  int _lastMergedValue = -1;
  bool _lastIsOver = false;
  bool _lastMoveNoMerge = false;

  /// 合并欢呼阈值（合成 ≥ 128 的棋子才欢呼）
  static const int _celebrateThreshold = 128;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _scheduleNextBlink();
  }

  void _initAnimations() {
    // 眼球：120ms 平滑过渡
    _eyeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _eyeAnimation = Tween<Offset>(begin: Offset.zero, end: Offset.zero).animate(
        CurvedAnimation(parent: _eyeController, curve: Curves.easeOut));

    // 身体跳跃：480ms 弹跳序列（上弹 → 超出 → 回弹 → 落地）
    _bodyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _bodyAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -22.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: -22.0, end: 5.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 5.0, end: -10.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 0.0), weight: 30),
    ]).animate(
        CurvedAnimation(parent: _bodyController, curve: Curves.easeInOut));

    // 表情：200ms 平滑过渡
    _expressionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _expressionAnimation = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _expressionController, curve: Curves.easeInOut),
    );

    // 空闲浮动：2200ms 往返循环，±3px 上下漂浮
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _idleAnimation = Tween<double>(begin: -3.0, end: 3.0).animate(
        CurvedAnimation(parent: _idleController, curve: Curves.easeInOut));

    // 头部倾斜：复用 _eyeController，初始正立
    _tiltAnimation = Tween<double>(begin: 0.0, end: 0.0).animate(
        CurvedAnimation(parent: _eyeController, curve: Curves.easeOut));

    // 棋盘掀起晃动：240ms 弹回，初始静止
    _wobbleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _wobbleAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(_wobbleController);

    // 眨眼：90ms（前半闭合，后半睁开）
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
    );
    _blinkAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.05), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 0.05, end: 1.0), weight: 50),
    ]).animate(_blinkController);
  }

  /// 随机间隔眨眼（2.5s ~ 5.5s）
  void _scheduleNextBlink() {
    final delay = Duration(milliseconds: 2500 + math.Random().nextInt(3000));
    Future.delayed(delay, () {
      if (!mounted) return;
      // 开心时眼睛已是弧形，跳过眨眼避免视觉冲突
      if (_expressionAnimation.value < 0.5) {
        _blinkController.forward(from: 0.0);
      }
      _scheduleNextBlink();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<GameProvider>();
    if (_watchedProvider != provider) {
      _watchedProvider?.removeListener(_onGameChanged);
      _watchedProvider = provider;
      _watchedProvider!.addListener(_onGameChanged);
    }
  }

  /// GameProvider 状态变化回调：分层响应，各层互不干扰
  void _onGameChanged() {
    if (!mounted) return;
    final game = _watchedProvider!;

    // 1. 眼球跟随滑动方向（每次 move 都会更新）
    if (game.lastMoveDirection != _lastDirection) {
      _lastDirection = game.lastMoveDirection;
      _moveEyes(game.lastMoveDirection);
      _triggerWobble(game.lastMoveDirection);
    }

    // 2. 无合并惋惜/生气（有效滑动但啕并未合）
    if (game.lastMoveNoMerge != _lastMoveNoMerge) {
      _lastMoveNoMerge = game.lastMoveNoMerge;
      if (game.lastMoveNoMerge) _reactToNoMerge();
    }

    // 3. 合并欢呼（阈値 ≥ 128，按合并数大小递进）
    if (game.lastMergedValue != _lastMergedValue) {
      _lastMergedValue = game.lastMergedValue;
      if (game.lastMergedValue >= _celebrateThreshold) {
        _celebrate(game.lastMergedValue);
      }
    }

    // 3. 游戏结束 / 重开
    if (game.isOver != _lastIsOver) {
      _lastIsOver = game.isOver;
      _setExpression(game.isOver ? -1.0 : 0.0);
    }
  }

  /// 跟随棋盘掀起效果晃动（爬墙头感）
  /// 棋盘往左翻 → 她向右晃；棋盘往上翻 → 她微微前倾
  void _triggerWobble(Direction? dir) {
    const sx = 3.5; // 横向晃动幅度 px
    const sy = 2.0; // 纵向抖动幅度 px
    final peak = switch (dir) {
      Direction.left => const Offset(sx, sy),
      Direction.right => const Offset(-sx, sy),
      Direction.up => const Offset(0, -sy * 1.2),
      Direction.down => const Offset(0, sy),
      null => Offset.zero,
    };
    _wobbleAnimation = TweenSequence<Offset>([
      TweenSequenceItem(
        tween: Tween<Offset>(begin: Offset.zero, end: peak),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<Offset>(begin: peak, end: Offset.zero),
        weight: 70,
      ),
    ]).animate(
        CurvedAnimation(parent: _wobbleController, curve: Curves.easeOut));
    _wobbleController.forward(from: 0.0);
  }

  /// 眼球+头部倾斜同步更新：从当前值流畅插值，疯狂滑动不跳变
  void _moveEyes(Direction? dir) {
    const maxPx = 5.0;
    final eyeTarget = switch (dir) {
      Direction.left => const Offset(-maxPx, 0),
      Direction.right => const Offset(maxPx, 0),
      Direction.up => const Offset(0, -maxPx),
      Direction.down => const Offset(0, maxPx),
      null => Offset.zero,
    };
    // 头部倾斜：左右滑动时向同方向偏转 ~6°，上下不倾斜
    final tiltTarget = switch (dir) {
      Direction.left => -0.10,
      Direction.right => 0.10,
      _ => 0.0,
    };
    final curEye = _eyeAnimation.value;
    final curTilt = _tiltAnimation.value;
    _eyeAnimation = Tween<Offset>(begin: curEye, end: eyeTarget).animate(
        CurvedAnimation(parent: _eyeController, curve: Curves.easeOut));
    _tiltAnimation = Tween<double>(begin: curTilt, end: tiltTarget).animate(
        CurvedAnimation(parent: _eyeController, curve: Curves.easeOut));
    _eyeController.forward(from: 0.0);
  }

  /// 无合并时惋惜/生气：短暂表现 -0.5（碗小气），然后恢复中性
  void _reactToNoMerge() {
    _setExpression(-0.5);
    Future.delayed(const Duration(milliseconds: 750), () {
      if (mounted && !(_watchedProvider?.isOver ?? false)) {
        _setExpression(0.0);
      }
    });
  }

  /// 欢呼：合并数大小决定喜悦度，跳跃时长随喜悦度延长
  void _celebrate(int mergeValue) {
    final joy = mergeValue >= 1024
        ? 1.0
        : mergeValue >= 512
            ? 0.80
            : mergeValue >= 256
                ? 0.60
                : 0.38; // 128
    _setExpression(joy);
    // 新欢呼直接重启，不排队，避免动画堆积
    _bodyController.forward(from: 0.0);
    final holdMs = 700 + (joy * 600).round();
    Future.delayed(Duration(milliseconds: holdMs), () {
      if (mounted && !(_watchedProvider?.isOver ?? false)) {
        _setExpression(0.0);
      }
    });
  }

  /// 表情切换：从当前插值位置平滑过渡到目标值
  void _setExpression(double target) {
    final current = _expressionAnimation.value;
    _expressionAnimation = Tween<double>(begin: current, end: target).animate(
      CurvedAnimation(parent: _expressionController, curve: Curves.easeInOut),
    );
    _expressionController.forward(from: 0.0);
  }

  @override
  void dispose() {
    _watchedProvider?.removeListener(_onGameChanged);
    _eyeController.dispose();
    _bodyController.dispose();
    _expressionController.dispose();
    _idleController.dispose();
    _wobbleController.dispose();
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      // 最外层：身体跳跃 + 空闲浮动叠加（GPU translate）
      child: AnimatedBuilder(
        animation: Listenable.merge(
            [_bodyController, _idleController, _wobbleController]),
        builder: (context, child) => Transform.translate(
          offset: Offset(
            _wobbleAnimation.value.dx,
            _bodyAnimation.value +
                _idleAnimation.value +
                _wobbleAnimation.value.dy,
          ),
          child: child,
        ),
        // 中间层：头部倾斜（GPU rotate）
        child: AnimatedBuilder(
          animation: _eyeController,
          builder: (context, child) => Transform.rotate(
            angle: _tiltAnimation.value,
            child: child,
          ),
          child: SizedBox(
            width: 68,
            height: 84,
            // 内层：眼球 + 眨眼 + 表情
            child: AnimatedBuilder(
              animation: Listenable.merge(
                  [_eyeController, _blinkController, _expressionController]),
              builder: (context, _) => CustomPaint(
                painter: _MascotFacePainter(
                  eyeOffset: _eyeAnimation.value,
                  blinkScale: _blinkAnimation.value,
                  expressionValue: _expressionAnimation.value,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// XIAOYO 可爱泰迪狗 Painter（68×84 画布）
/// expressionValue 语义：
///   -1.0 = 难过（游戏结束）
///   -0.5 = 惋惜/生气（无合并）
///    0.0 = 中性
///   +0.38/0.60/0.80/1.0 = 递进喜悦（128/256/512/1024+）
class _MascotFacePainter extends CustomPainter {
  final Offset eyeOffset;
  final double blinkScale;
  final double expressionValue;

  const _MascotFacePainter({
    required this.eyeOffset,
    required this.blinkScale,
    required this.expressionValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final faceR = size.width * 0.38;
    final faceCy = size.height * 0.44;

    _drawEars(canvas, cx, faceCy, faceR);
    _drawFace(canvas, cx, faceCy, faceR);
    _drawEyes(canvas, cx, faceCy, faceR);
    _drawNose(canvas, cx, faceCy, faceR);
    _drawMouth(canvas, cx, faceCy, faceR);
    if (expressionValue > 0.08) _drawBlush(canvas, cx, faceCy, faceR);
    _drawPaws(canvas, size, cx, faceCy, faceR);
  }

  // ── 下垂的狗狗耳朵 ──
  void _drawEars(Canvas canvas, double cx, double faceCy, double faceR) {
    final earSpacing = faceR * 0.55;
    final earW = faceR * 0.28;
    final earH = faceR * 0.55;
    final earBaseY = faceCy - faceR * 0.45;

    for (final side in [-1.0, 1.0]) {
      final ex = cx + side * earSpacing;
      // 下垂的椭圆耳朵
      final earOval = Rect.fromCenter(
        center: Offset(ex, earBaseY + earH * 0.2),
        width: earW,
        height: earH,
      );
      // 外耳
      canvas.drawOval(
        earOval,
        Paint()..color = const Color(0xFF6B5637),
      );
      // 内耳（浅色）
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(ex, earBaseY + earH * 0.2),
          width: earW * 0.7,
          height: earH * 0.8,
        ),
        Paint()..color = const Color(0xFF8B6F47),
      );
    }
  }

  // ── 泰迪狗脸：棕褐色渐变 ──
  void _drawFace(Canvas canvas, double cx, double faceCy, double faceR) {
    final center = Offset(cx, faceCy);
    final rect = Rect.fromCircle(center: center, radius: faceR);
    // 棕褐色径向渐变
    final shader = const RadialGradient(
      center: Alignment(-0.15, -0.20),
      radius: 0.85,
      colors: [Color(0xFFA0826D), Color(0xFF8B6F47)],
    ).createShader(rect);
    canvas.drawCircle(center, faceR, Paint()..shader = shader);
    // 简单轮廓线
    canvas.drawCircle(
      center,
      faceR,
      Paint()
        ..color = const Color(0xFF6B5637)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  // ── 大眼睛：纯黑瞳孔 + 白色高光 ──
  void _drawEyes(Canvas canvas, double cx, double faceCy, double faceR) {
    final eyeY = faceCy - faceR * 0.18;
    final spacing = faceR * 0.48;
    final eyeR = faceR * 0.32;
    final pupilR = eyeR * 0.45;
    final maxOff = eyeR * 0.25;

    for (final side in [-1.0, 1.0]) {
      final ex = cx + side * spacing;
      canvas.save();
      canvas.translate(ex, eyeY);

      if (expressionValue > 0.55) {
        // 开心：弯眼 ^^
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(0, eyeR * 0.15),
            width: eyeR * 2.2,
            height: eyeR * 1.8,
          ),
          math.pi * 0.15,
          math.pi * 0.7,
          false,
          Paint()
            ..color = const Color(0xFF2C1810)
            ..strokeWidth = 2.8
            ..strokeCap = StrokeCap.round,
        );
      } else {
        // 普通/难过：圆眼
        canvas.save();
        canvas.scale(1.0, blinkScale.clamp(0.06, 1.0));

        // 眼白（米白色）
        canvas.drawCircle(
          Offset.zero,
          eyeR,
          Paint()..color = const Color(0xFFF5E6D3),
        );

        // 瞳孔（纯黑，跟随滑动）
        final po = Offset(
          eyeOffset.dx.clamp(-maxOff, maxOff),
          eyeOffset.dy.clamp(-maxOff, maxOff),
        );
        canvas.drawCircle(po, pupilR, Paint()..color = const Color(0xFF2C1810));

        // 高光
        canvas.drawCircle(
          Offset(po.dx - pupilR * 0.25, po.dy - pupilR * 0.25),
          pupilR * 0.35,
          Paint()..color = Colors.white.withOpacity(0.9),
        );
        canvas.drawCircle(
          Offset(po.dx + pupilR * 0.15, po.dy + pupilR * 0.12),
          pupilR * 0.12,
          Paint()..color = Colors.white.withOpacity(0.6),
        );

        canvas.restore();
      }

      canvas.restore();
    }
  }

  // ── 小黑鼻子 ──
  void _drawNose(Canvas canvas, double cx, double faceCy, double faceR) {
    canvas.drawCircle(
      Offset(cx, faceCy + faceR * 0.08),
      faceR * 0.055,
      Paint()..color = const Color(0xFF2C1810),
    );
    // 鼻子高光
    canvas.drawCircle(
      Offset(cx - faceR * 0.01, faceCy + faceR * 0.065),
      faceR * 0.02,
      Paint()..color = Colors.white.withOpacity(0.4),
    );
  }

  // ── 嘴巴：可爱微笑/委屈下撇 ──
  void _drawMouth(Canvas canvas, double cx, double faceCy, double faceR) {
    final my = faceCy + faceR * 0.35;
    final hw = faceR * 0.25;
    final curvature = expressionValue * faceR * 0.15;

    if (expressionValue < -0.3) {
      // 委屈：下撇嘴
      canvas.drawPath(
        Path()
          ..moveTo(cx - hw, my)
          ..quadraticBezierTo(cx, my + curvature - faceR * 0.02, cx + hw, my),
        Paint()
          ..color = const Color(0xFF6B5637)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round,
      );
    } else {
      // 微笑：上扬嘴
      canvas.drawPath(
        Path()
          ..moveTo(cx - hw, my)
          ..quadraticBezierTo(cx, my + curvature + faceR * 0.03, cx + hw, my),
        Paint()
          ..color = const Color(0xFF6B5637)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  // ── 腮红：开心时显现 ──
  void _drawBlush(Canvas canvas, double cx, double faceCy, double faceR) {
    final alpha = (expressionValue * 80).round().clamp(0, 80);
    if (alpha == 0) return;
    final by = faceCy + faceR * 0.20;
    final bx = faceR * 0.65;
    final paint = Paint()..color = const Color(0xFFFFB6C1).withAlpha(alpha);
    canvas.drawCircle(Offset(cx - bx, by), faceR * 0.22, paint);
    canvas.drawCircle(Offset(cx + bx, by), faceR * 0.22, paint);
  }

  // ── 小爪子：紧扣棋盘 ──
  void _drawPaws(
      Canvas canvas, Size size, double cx, double faceCy, double faceR) {
    final pawY = faceCy + faceR + size.height * 0.065;
    final pawW = faceR * 0.55;
    final pawH = faceR * 0.28;
    final spacing = faceR * 0.65;

    for (final side in [-1.0, 1.0]) {
      final px = cx + side * spacing;
      final rRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(px, pawY), width: pawW, height: pawH),
        Radius.circular(pawH * 0.6),
      );
      // 爪子底色
      canvas.drawRRect(rRect, Paint()..color = const Color(0xFF8B6F47));
      // 轮廓
      canvas.drawRRect(
        rRect,
        Paint()
          ..color = const Color(0xFF6B5637)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
      // 肉垫（深棕）
      final padR = pawH * 0.15;
      for (int i = -1; i <= 1; i++) {
        canvas.drawCircle(
          Offset(px + i * pawW * 0.25, pawY - pawH * 0.06),
          padR,
          Paint()..color = const Color(0xFF6B5637),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MascotFacePainter old) =>
      old.eyeOffset != eyeOffset ||
      old.blinkScale != blinkScale ||
      old.expressionValue != expressionValue;
}
