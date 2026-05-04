import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/features/game_2048/providers/game_provider.dart';
import 'package:yueyou/features/audio/services/tts_engine_service.dart';

/// 棋盘吉祥物 —— 趴在棋盘上方，眼球跟随玩家滑动方向
/// 合成大棋子时欢呼跳跃，失败时陪你一起难过
///
/// 架构设计：纯渲染组件，不处理手势，通过 onTap 回调接收点击事件
class BoardMascot extends ConsumerStatefulWidget {
  /// 点击回调（由父组件 DashboardScreen 触发）
  final VoidCallback? onTap;

  const BoardMascot({super.key, this.onTap});

  @override
  ConsumerState<BoardMascot> createState() => BoardMascotState();
}

class BoardMascotState extends ConsumerState<BoardMascot>
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

  // ── 头部倾斜（复用 _eyeController 同步，左右滑动各 ±6°）──
  late Animation<double> _tiltAnimation;

  // ── 跟随棋盘掀起的晃动（每次滑动触发，爬墙头感）──
  late AnimationController _wobbleController;
  late Animation<Offset> _wobbleAnimation;

  // ── 眨眼层（独立随机循环，与其他层完全解耦）──
  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;
  Timer? _blinkTimer;

  // ── 点击能量脉冲层 ──
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // ── GameProvider 监听 ──
  GameProvider? _watchedProvider;
  Direction? _lastDirection;
  int _lastMergedValue = -1;
  bool _lastIsOver = false;
  bool _lastMoveNoMerge = false;

  TtsEngineService? _watchedTtsProvider;
  bool _hasTtsError = false;

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
      duration: CyberDimensions.animInstant,
    );
    _eyeAnimation = Tween<Offset>(begin: Offset.zero, end: Offset.zero).animate(
      CurvedAnimation(parent: _eyeController, curve: Curves.easeOut),
    );

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
      CurvedAnimation(parent: _bodyController, curve: Curves.easeInOut),
    );

    // 表情：200ms 平滑过渡
    _expressionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _expressionAnimation = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _expressionController, curve: Curves.easeInOut),
    );

    // 头部倾斜：复用 _eyeController，初始正立
    _tiltAnimation = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _eyeController, curve: Curves.easeOut),
    );

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

    // 能量脉冲：点击时触发，600ms 扩散消失
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
  }

  /// 随机间隔眨眼（2.5s ~ 5.5s）
  void _scheduleNextBlink() {
    _blinkTimer?.cancel();
    final delay = Duration(milliseconds: 2500 + math.Random().nextInt(3000));
    _blinkTimer = Timer(delay, () {
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
    final provider = ref.read(gameProvider);
    if (_watchedProvider != provider) {
      _watchedProvider?.removeListener(_onGameChanged);
      _watchedProvider = provider;
      _watchedProvider!.addListener(_onGameChanged);
    }
    final ttsProvider = ref.read(ttsEngineProvider);
    if (_watchedTtsProvider != ttsProvider) {
      _watchedTtsProvider?.removeListener(_onTtsChanged);
      _watchedTtsProvider = ttsProvider;
      _watchedTtsProvider!.addListener(_onTtsChanged);
      _hasTtsError = ttsProvider.lastError != null;
    }
  }

  void _onTtsChanged() {
    if (!mounted) return;
    final hasError = _watchedTtsProvider!.lastError != null;
    if (_hasTtsError != hasError) {
      setState(() {
        _hasTtsError = hasError;
      });
      if (hasError) {
        _setExpression(-1.0);
      } else {
        if (!(_watchedProvider?.isOver ?? false)) {
          _setExpression(0.0);
        }
      }
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
      CurvedAnimation(parent: _wobbleController, curve: Curves.easeOut),
    );
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
      CurvedAnimation(parent: _eyeController, curve: Curves.easeOut),
    );
    _tiltAnimation = Tween<double>(begin: curTilt, end: tiltTarget).animate(
      CurvedAnimation(parent: _eyeController, curve: Curves.easeOut),
    );
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
    _blinkTimer?.cancel();
    _watchedProvider?.removeListener(_onGameChanged);
    _watchedTtsProvider?.removeListener(_onTtsChanged);
    _eyeController.dispose();
    _bodyController.dispose();
    _expressionController.dispose();
    _wobbleController.dispose();
    _blinkController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// 触发点击动画（由外部回调调用）
  void triggerTapAnimation() {
    // 能量脉冲
    _pulseController.forward(from: 0.0);
    // 眼睛快速眨一下
    _blinkController.forward(from: 0.0).then((_) {
      if (mounted) _blinkController.reverse();
    });
    // 轻微跳跃
    _bodyController.forward(from: 0.0);
    // 开心表情
    _setExpression(0.8);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && !(_watchedProvider?.isOver ?? false)) {
        _setExpression(0.0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      height: 84,
      child: RepaintBoundary(
        // 最外层：身体跳跃 + 晃动（移除空闲浮动）
        child: AnimatedBuilder(
          animation: Listenable.merge([_bodyController, _wobbleController]),
          builder: (context, child) => Transform.translate(
            offset: Offset(
              _wobbleAnimation.value.dx,
              _bodyAnimation.value + _wobbleAnimation.value.dy,
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
            // 内层：眼球 + 眨眼 + 表情 + 脉冲波（OverflowBox 允许波纹超出布局边界）
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _eyeController,
                _blinkController,
                _expressionController,
                _pulseController,
              ]),
              builder: (context, _) => OverflowBox(
                maxWidth: 200,
                maxHeight: 200,
                child: CustomPaint(
                  size: const Size(200, 200),
                  painter: _MascotFacePainter(
                    eyeOffset: _eyeAnimation.value,
                    blinkScale: _blinkAnimation.value,
                    expressionValue: _expressionAnimation.value,
                    pulseValue: _pulseAnimation.value,
                    hasError: _hasTtsError,
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
  final double pulseValue;
  final bool hasError;

  static const double _mW = 68.0;
  static const double _mH = 84.0;

  const _MascotFacePainter({
    required this.eyeOffset,
    required this.blinkScale,
    required this.expressionValue,
    required this.pulseValue,
    required this.hasError,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 画布中心 = 吉祥物中心（OverflowBox 居中对齐）
    final cx = size.width / 2;
    // 吉祥物顶部在画布中的偏移
    final offsetY = (size.height - _mH) / 2;
    const coreR = _mW * 0.32;
    final coreCy = offsetY + _mH * 0.40;

    _drawTentacles(canvas, cx, offsetY, coreCy, coreR);
    _drawCore(canvas, cx, coreCy, coreR);
    _drawEyes(canvas, cx, coreCy, coreR);
    _drawMouth(canvas, cx, coreCy, coreR);

    if (pulseValue > 0.0) {
      _drawPulseWave(canvas, cx, coreCy, coreR);
    }
  }

  // ── 能量脉冲波：点击时从核心扩散 ──
  void _drawPulseWave(Canvas canvas, double cx, double coreCy, double coreR) {
    final center = Offset(cx, coreCy);
    final fade = 1.0 - pulseValue; // 1.0→0.0 逐渐消失
    final themeColor = hasError ? CyberColors.neonPink : CyberColors.hackerBlue;

    // 第一圈（最外层，扩散最远）
    final r1 = coreR * (1.0 + pulseValue * 2.2);
    canvas.drawCircle(
      center,
      r1,
      Paint()
        ..color = themeColor.withValues(alpha: fade * 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // 第二圈（中层）
    final r2 = coreR * (1.0 + pulseValue * 1.4);
    canvas.drawCircle(
      center,
      r2,
      Paint()
        ..color = themeColor.withValues(alpha: fade * 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // 第三圈（最内层，最亮，扩散最慢）
    final r3 = coreR * (1.0 + pulseValue * 0.7);
    canvas.drawCircle(
      center,
      r3,
      Paint()
        ..color = themeColor.withValues(alpha: fade * 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  // ── 能量触手：抓住边框 + 能量扩散 ──
  void _drawTentacles(
    Canvas canvas,
    double cx,
    double offsetY,
    double coreCy,
    double coreR,
  ) {
    final tentacleTop = coreCy + coreR * 0.8;
    final tentacleBottom = offsetY + _mH;
    final spacing = coreR * 0.85;
    final themeColor = hasError ? CyberColors.neonPink : CyberColors.hackerBlue;

    for (final side in [-1.0, 1.0]) {
      final tx = cx + side * spacing;

      // 触手路径（贝塞尔曲线，更有机感）
      final path = Path()
        ..moveTo(tx, tentacleTop)
        ..quadraticBezierTo(
          tx + side * 3,
          (tentacleTop + tentacleBottom) * 0.5,
          tx + side * 2,
          tentacleBottom,
        );

      // 底部能量扩散效果（融入边框）
      final bottomX = tx + side * 2;
      canvas.drawCircle(
        Offset(bottomX, tentacleBottom),
        12.0,
        Paint()
          ..color = themeColor.withValues(alpha: 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawCircle(
        Offset(bottomX, tentacleBottom),
        6.0,
        Paint()
          ..color = themeColor.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );

      // 外发光（霓虹效果）
      canvas.drawPath(
        path,
        Paint()
          ..color = themeColor.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8.0
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );

      // 核心线条
      canvas.drawPath(
        path,
        Paint()
          ..color = themeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );

      // 能量节点（3个脉冲发光点）
      for (int i = 0; i < 3; i++) {
        final t = 0.25 + i * 0.25;
        final nodeY = tentacleTop + (tentacleBottom - tentacleTop) * t;
        final nodeX = tx + side * (3 * (1 - t) + 2 * t);

        // 外外层发光（脉冲效果）
        canvas.drawCircle(
          Offset(nodeX, nodeY),
          5.0,
          Paint()
            ..color = themeColor.withValues(alpha: 0.2)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
        // 外发光
        canvas.drawCircle(
          Offset(nodeX, nodeY),
          3.5,
          Paint()
            ..color = themeColor.withValues(alpha: 0.5)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        // 核心点
        canvas.drawCircle(
          Offset(nodeX, nodeY),
          1.8,
          Paint()..color = themeColor,
        );
        // 高光
        canvas.drawCircle(
          Offset(nodeX - 0.5, nodeY - 0.5),
          0.8,
          Paint()..color = CyberColors.white,
        );
      }
    }
  }

  // ── 核心球体：发光的赛博生命体 + 双层光晕 ──
  void _drawCore(Canvas canvas, double cx, double coreCy, double coreR) {
    final center = Offset(cx, coreCy);
    final rect = Rect.fromCircle(center: center, radius: coreR);
    final themeColor = hasError ? CyberColors.neonPink : CyberColors.hackerBlue;

    // 外外层光晕（远距离辐射）
    canvas.drawCircle(
      center,
      coreR + 12,
      Paint()
        ..color = themeColor.withValues(alpha: 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // 外发光层（霓虹光晕）
    canvas.drawCircle(
      center,
      coreR + 6,
      Paint()
        ..color = themeColor.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // 主体渐变（深黑到半透明青或粉）
    final shader = RadialGradient(
      center: const Alignment(-0.2, -0.3),
      radius: 0.9,
      colors: [
        CyberColors.surface,
        CyberColors.background,
        themeColor.withValues(alpha: hasError ? 0.25 : 0.15),
      ],
      stops: const [0.0, 0.6, 1.0],
    ).createShader(rect);
    canvas.drawCircle(center, coreR, Paint()..shader = shader);

    // 霓虹边框（双层）
    canvas.drawCircle(
      center,
      coreR + 0.5,
      Paint()
        ..color = themeColor.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    canvas.drawCircle(
      center,
      coreR,
      Paint()
        ..color = themeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );

    // 内部脉冲圆环（根据表情值动态缩放）
    final pulseR = coreR * (0.5 + expressionValue.abs() * 0.2);
    canvas.drawCircle(
      center,
      pulseR,
      Paint()
        ..color = themeColor.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // 核心点（最亮点）
    canvas.drawCircle(
      Offset(cx - coreR * 0.15, coreCy - coreR * 0.2),
      coreR * 0.08,
      Paint()
        ..color = themeColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  // ── 霓虹眼睛：发光的追踪点 ──
  void _drawEyes(Canvas canvas, double cx, double coreCy, double coreR) {
    final eyeY = coreCy - coreR * 0.18;
    final spacing = coreR * 0.50;
    final eyeR = coreR * 0.12;
    final maxOff = coreR * 0.15;
    final themeColor = hasError ? CyberColors.neonPink : CyberColors.hackerBlue;

    for (final side in [-1.0, 1.0]) {
      final ex = cx + side * spacing;

      if (expressionValue > 0.55) {
        // 开心：发光弧线 ^
        final arcPath = Path()
          ..addArc(
            Rect.fromCenter(
              center: Offset(ex, eyeY + eyeR * 0.3),
              width: eyeR * 3.5,
              height: eyeR * 2.5,
            ),
            math.pi * 0.2,
            math.pi * 0.6,
          );

        // 外发光
        canvas.drawPath(
          arcPath,
          Paint()
            ..color = themeColor.withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4.0
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        // 核心线
        canvas.drawPath(
          arcPath,
          Paint()
            ..color = themeColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0
            ..strokeCap = StrokeCap.round,
        );
      } else {
        // 错误状态闭眼或跟随滑动
        final double currentBlink = hasError ? 0.1 : blinkScale.clamp(0.1, 1.0);
        // 普通/错误：发光圆点（跟随滑动）
        canvas.save();
        canvas.translate(ex, eyeY);
        canvas.scale(1.0, currentBlink);

        final po = Offset(
          eyeOffset.dx.clamp(-maxOff, maxOff),
          eyeOffset.dy.clamp(-maxOff, maxOff),
        );

        // 外外层发光（增强辐射）
        canvas.drawCircle(
          po,
          eyeR + 5,
          Paint()
            ..color = themeColor.withValues(alpha: 0.25)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );

        // 外发光
        canvas.drawCircle(
          po,
          eyeR + 3,
          Paint()
            ..color = themeColor.withValues(alpha: 0.5)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );

        // 核心点
        canvas.drawCircle(
          po,
          eyeR,
          Paint()..color = themeColor,
        );

        // 高光（更亮）
        canvas.drawCircle(
          po + Offset(-eyeR * 0.3, -eyeR * 0.3),
          eyeR * 0.4,
          Paint()..color = CyberColors.white,
        );

        canvas.restore();
      }
    }
  }

  // ── 霓虹嘴巴：发光弧线 ──
  void _drawMouth(Canvas canvas, double cx, double coreCy, double coreR) {
    final my = coreCy + coreR * 0.35;
    final hw = coreR * 0.35;
    final curvature = expressionValue * coreR * 0.22;
    final themeColor = hasError ? CyberColors.neonPink : CyberColors.hackerBlue;

    final mouthPath = Path()
      ..moveTo(cx - hw, my)
      ..quadraticBezierTo(
        cx,
        my +
            curvature +
            (expressionValue < -0.3 ? -coreR * 0.05 : coreR * 0.08),
        cx + hw,
        my,
      );

    // 外发光
    canvas.drawPath(
      mouthPath,
      Paint()
        ..color = themeColor.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // 核心线
    canvas.drawPath(
      mouthPath,
      Paint()
        ..color = themeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_MascotFacePainter old) =>
      old.eyeOffset != eyeOffset ||
      old.blinkScale != blinkScale ||
      old.expressionValue != expressionValue ||
      old.pulseValue != pulseValue ||
      old.hasError != hasError;
}
