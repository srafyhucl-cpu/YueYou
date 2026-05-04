import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rive/rive.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/features/game_2048/providers/game_provider.dart';

/// XIAOYO 吉祥物 - Rive 动画版本
///
/// 功能：
/// - 眼球跟随滑动方向 (lookX, lookY)
/// - 合并方块时欢呼 (onMerge trigger)
/// - 游戏结束时难过 (isGameOver boolean)
///
/// 布局约束：
/// - 尺寸固定 68×84，爪子位置在 73px 处
/// - 通过 LayoutBuilder 精确定位到棋盘上边框
class BoardMascotRive extends ConsumerStatefulWidget {
  const BoardMascotRive({super.key});

  @override
  ConsumerState<BoardMascotRive> createState() => _BoardMascotRiveState();
}

class _BoardMascotRiveState extends ConsumerState<BoardMascotRive> {
  // Rive 核心控制器
  Artboard? _riveArtboard;
  StateMachineController? _controller;

  // 状态机输入（名称必须与 .riv 文件中的输入名称一致）
  SMINumber? _lookXInput;
  SMINumber? _lookYInput;
  SMITrigger? _onMergeInput;
  SMIBool? _isGameOverInput;

  // 缓存上一次的状态，避免重复触发
  Direction? _lastDirection;
  int _lastMergedValue = -1;
  bool _lastIsOver = false;

  // GameProvider 监听（与 BoardMascot 保持一致的响应式模式）
  GameProvider? _watchedProvider;

  @override
  void initState() {
    super.initState();
    _loadRiveFile();
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
  }

  /// GameProvider 状态变化回调：仅更新 Rive 状态机输入，不触发 Widget rebuild
  void _onGameChanged() {
    if (!mounted || _watchedProvider == null) return;
    _updateRiveInputs(_watchedProvider!);
  }

  /// 加载 Rive 文件并初始化状态机
  Future<void> _loadRiveFile() async {
    try {
      final data = await rootBundle.load('assets/rive/xiaoyo.riv');
      final file = RiveFile.import(data);

      // 尝试获取 mainArtboard，如果失败则使用第一个 artboard
      final artboard = file.mainArtboard;

      // 尝试查找状态机（Lil Guy 可能使用不同的状态机名称）
      StateMachineController? controller;

      // 先尝试默认名称
      controller =
          StateMachineController.fromArtboard(artboard, 'MainStateMachine');

      // 如果找不到，尝试其他常见名称
      controller ??=
          StateMachineController.fromArtboard(artboard, 'State Machine 1');

      if (controller != null) {
        artboard.addController(controller);
        _controller = controller;

        // 绑定输入（如果 .riv 文件中的输入名称不同，需要修改这里）
        _lookXInput = controller.findInput<double>('lookX') as SMINumber?;
        _lookYInput = controller.findInput<double>('lookY') as SMINumber?;
        _onMergeInput = controller.findInput<bool>('onMerge') as SMITrigger?;
        _isGameOverInput = controller.findInput<bool>('isGameOver') as SMIBool?;

        final missingInputs = <String>[
          if (_lookXInput == null) 'lookX',
          if (_lookYInput == null) 'lookY',
          if (_onMergeInput == null) 'onMerge',
          if (_isGameOverInput == null) 'isGameOver',
        ];
        if (missingInputs.isNotEmpty) {
          CyberLogger.captureWarning(
            StateError('Rive 状态机输入未找到'),
            tag: 'game',
            extra: {'missingInputs': missingInputs.join(', ')},
          );
        }
      } else {
        CyberLogger.captureWarning(
          StateError('Rive 状态机未找到'),
          tag: 'game',
          extra: {'context': 'MainStateMachine 与 State Machine 1 均不存在'},
        );
      }

      if (mounted) {
        setState(() => _riveArtboard = artboard);
      }
    } catch (e, stackTrace) {
      CyberLogger.captureWarning(
        e,
        stack: stackTrace,
        tag: 'game',
        extra: {'context': 'Rive 文件加载失败'},
      );
    }
  }

  @override
  void dispose() {
    _watchedProvider?.removeListener(_onGameChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // build() 纯函数：Rive 状态机输入由 _onGameChanged 驱动，此处只负责渲染
    return SizedBox(
      width: 68,
      height: 84,
      child: _riveArtboard == null
          ? const Center(
              child: CircularProgressIndicator(
                color: CyberColors.whiteSubtle,
                strokeWidth: 2,
              ),
            )
          : Rive(
              artboard: _riveArtboard!,
              fit: BoxFit.contain,
            ),
    );
  }

  /// 根据 GameProvider 状态更新 Rive 输入
  void _updateRiveInputs(GameProvider game) {
    // 1. 眼球跟随滑动方向
    if (game.lastMoveDirection != _lastDirection) {
      _lastDirection = game.lastMoveDirection;
      _updateLookDirection(game.lastMoveDirection);
    }

    // 2. 合并欢呼（阈值 >= 128）
    if (game.lastMergedValue != _lastMergedValue) {
      _lastMergedValue = game.lastMergedValue;
      if (game.lastMergedValue >= 128) {
        _onMergeInput?.fire();
      }
    }

    // 3. 游戏结束状态
    if (game.isOver != _lastIsOver) {
      _lastIsOver = game.isOver;
      _isGameOverInput?.value = game.isOver;
    }
  }

  /// 将滑动方向映射为 lookX/lookY 值
  void _updateLookDirection(Direction? direction) {
    if (direction == null) return;

    switch (direction) {
      case Direction.up:
        _lookXInput?.value = 0.0;
        _lookYInput?.value = -1.0;
        break;
      case Direction.down:
        _lookXInput?.value = 0.0;
        _lookYInput?.value = 1.0;
        break;
      case Direction.left:
        _lookXInput?.value = -1.0;
        _lookYInput?.value = 0.0;
        break;
      case Direction.right:
        _lookXInput?.value = 1.0;
        _lookYInput?.value = 0.0;
        break;
    }
  }
}
