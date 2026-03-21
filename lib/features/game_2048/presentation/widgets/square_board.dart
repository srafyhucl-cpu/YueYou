import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/features/game_2048/providers/game_provider.dart';
import 'package:yueyou/features/game_2048/domain/tile_model.dart';
import 'tile_widget.dart';
import 'board_reset_animation.dart';

/// 2048 棋盘主组件
/// 物理引擎重构：Stack + AnimatedPositioned 实现丝滑滑动动画
class SquareBoard extends StatefulWidget {
  const SquareBoard({super.key});

  @override
  State<SquareBoard> createState() => _SquareBoardState();
}

class _SquareBoardState extends State<SquareBoard>
    with SingleTickerProviderStateMixin {
  double _accumulatedDx = 0;
  double _accumulatedDy = 0;
  bool _hasMoved = false;
  late AnimationController _tiltController;
  late Animation<double> _tiltX;
  late Animation<double> _tiltY;

  @override
  void initState() {
    super.initState();
    _tiltController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _tiltX = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _tiltController, curve: Curves.easeOut),
    );
    _tiltY = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _tiltController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    if (_tiltController.isAnimating) {
      _tiltController.stop();
    }
    _tiltController.dispose();
    super.dispose();
  }

  void _triggerTilt(Direction direction) {
    const tiltAngle = 0.08; // 约5度
    double targetX = 0;
    double targetY = 0;

    switch (direction) {
      case Direction.up:
        targetX = tiltAngle;
        break;
      case Direction.down:
        targetX = -tiltAngle;
        break;
      case Direction.left:
        targetY = tiltAngle;
        break;
      case Direction.right:
        targetY = -tiltAngle;
        break;
    }

    setState(() {
      _tiltX = Tween<double>(begin: 0, end: targetX).animate(
        CurvedAnimation(parent: _tiltController, curve: Curves.easeOut),
      );
      _tiltY = Tween<double>(begin: 0, end: targetY).animate(
        CurvedAnimation(parent: _tiltController, curve: Curves.easeOut),
      );
    });

    _tiltController.forward().then((_) => _tiltController.reverse());
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();

    return AnimatedBuilder(
      animation: _tiltController,
      builder: (context, child) {
        return Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateX(_tiltX.value)
            ..rotateY(_tiltY.value),
          alignment: Alignment.center,
          child: child,
        );
      },
      child: BoardResetAnimation(
        triggerReset: provider.score == 0 && provider.combo == 0,
        child: GestureDetector(
          onPanStart: (d) {
            _accumulatedDx = 0;
            _accumulatedDy = 0;
            _hasMoved = false;
          },
          onPanUpdate: (d) {
            if (_hasMoved) return;

            _accumulatedDx += d.delta.dx;
            _accumulatedDy += d.delta.dy;

            // 电竞级响应：累积超过20像素立即触发
            if (_accumulatedDx.abs() > 20 || _accumulatedDy.abs() > 20) {
              Direction direction;
              if (_accumulatedDx.abs() > _accumulatedDy.abs()) {
                direction =
                    _accumulatedDx > 0 ? Direction.right : Direction.left;
              } else {
                direction = _accumulatedDy > 0 ? Direction.down : Direction.up;
              }
              provider.move(direction);
              _triggerTilt(direction);
              _hasMoved = true;
            }
          },
          onPanEnd: (d) {
            _accumulatedDx = 0;
            _accumulatedDy = 0;
            _hasMoved = false;
          },
          child: RepaintBoundary(
            child: AspectRatio(
              aspectRatio: 1.0,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final boardSize = constraints.maxWidth;
                  const padding = 16.0;
                  const spacing = 10.0;
                  final cellSize = (boardSize - padding * 2 - spacing * 3) / 4;

                  return Selector<GameProvider, List<List<TileModel?>>>(
                    selector: (context, provider) => provider.board,
                    builder: (context, board, _) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(32.0),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: Container(
                            clipBehavior: Clip.none,
                            padding: const EdgeInsets.all(padding),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(32.0),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.12),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.5),
                                  blurRadius: 30,
                                  offset: const Offset(0, 10),
                                )
                              ],
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                // 背景网格
                                _buildBackgroundGrid(cellSize, spacing),
                                // 动画方块层
                                ...board
                                    .expand((row) => row)
                                    .where((tile) => tile != null)
                                    .map((tile) {
                                  final pos = _findTilePosition(board, tile!);
                                  return AnimatedPositioned(
                                    key: ValueKey(tile.id),
                                    duration: const Duration(milliseconds: 150),
                                    curve: Curves.easeOut,
                                    left: pos.$2 * (cellSize + spacing),
                                    top: pos.$1 * (cellSize + spacing),
                                    width: cellSize,
                                    height: cellSize,
                                    child: TileWidget(value: tile.value),
                                  );
                                }),
                                // 🔥 恢复 Game Over 毛玻璃遮罩
                                if (context.read<GameProvider>().isOver)
                                  Positioned.fill(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(24),
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(
                                            sigmaX: 10, sigmaY: 10),
                                        child: Container(
                                          color: Colors.black.withOpacity(0.7),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                'GAME OVER',
                                                style: TextStyle(
                                                  color: CyberColors.neonPink,
                                                  fontSize: 32,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 4,
                                                  shadows: [
                                                    Shadow(
                                                      color: CyberColors
                                                          .neonPink
                                                          .withOpacity(0.8),
                                                      blurRadius: 20,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(height: 24),
                                              ElevatedButton(
                                                onPressed: () {
                                                  context
                                                      .read<GameProvider>()
                                                      .reset();
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      CyberColors.neonCyan,
                                                  foregroundColor: Colors.black,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 32,
                                                    vertical: 16,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                  ),
                                                ),
                                                child: const Text(
                                                  'RESTART (重新连接)',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    letterSpacing: 1,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundGrid(double cellSize, double spacing) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
      ),
      itemCount: 16,
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(16.0),
          ),
        );
      },
    );
  }

  (int, int) _findTilePosition(List<List<TileModel?>> board, TileModel tile) {
    for (int r = 0; r < board.length; r++) {
      for (int c = 0; c < board[r].length; c++) {
        if (board[r][c]?.id == tile.id) {
          return (r, c);
        }
      }
    }
    return (0, 0);
  }
}
