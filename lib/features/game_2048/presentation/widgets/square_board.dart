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

class _SquareBoardState extends State<SquareBoard> {
  Offset? _dragStart;
  Offset? _dragUpdate;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();

    return BoardResetAnimation(
      triggerReset: provider.score == 0 && provider.combo == 0,
      child: GestureDetector(
        onPanStart: (d) => _dragStart = d.localPosition,
        onPanUpdate: (d) => _dragUpdate = d.localPosition,
        onPanEnd: (d) {
          if (_dragStart == null || _dragUpdate == null) return;
          final dx = _dragUpdate!.dx - _dragStart!.dx;
          final dy = _dragUpdate!.dy - _dragStart!.dy;

          if (dx.abs() > 25 || dy.abs() > 25) {
            if (dx.abs() > dy.abs()) {
              provider.move(dx > 0 ? Direction.right : Direction.left);
            } else {
              provider.move(dy > 0 ? Direction.down : Direction.up);
            }
          }
          _dragStart = null;
          _dragUpdate = null;
        },
        child: RepaintBoundary(
          child: AspectRatio(
            aspectRatio: 1.0,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final boardSize = constraints.maxWidth;
                final padding = 16.0;
                final spacing = 10.0;
                final cellSize = (boardSize - padding * 2 - spacing * 3) / 4;

                return Container(
                  padding: EdgeInsets.all(padding),
                  decoration: BoxDecoration(
                    color: CyberColors.cardBackground,
                    borderRadius: BorderRadius.circular(32.0),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.05),
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
                    children: [
                      // 背景网格
                      _buildBackgroundGrid(cellSize, spacing),
                      // 动画方块层
                      ...provider.board
                          .expand((row) => row)
                          .where((tile) => tile != null)
                          .map((tile) {
                        final pos = _findTilePosition(provider.board, tile!);
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
                      }).toList(),
                    ],
                  ),
                );
              },
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
