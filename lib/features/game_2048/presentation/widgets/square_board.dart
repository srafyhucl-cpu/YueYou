import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/features/game_2048/providers/game_provider.dart';
import 'tile_widget.dart';

/// 2048 棋盘主组件
/// 重构目标：纯粹的战斗网格，极致的性能与视觉
class SquareBoard extends StatefulWidget {
  const SquareBoard({super.key});

  @override
  State<SquareBoard> createState() => _SquareBoardState();
}

class _SquareBoardState extends State<SquareBoard> {
  // 手势追踪变量
  Offset? _dragStart;
  Offset? _dragUpdate;

  @override
  Widget build(BuildContext context) {
    // 监听最近的 Provider (由 DashboardScreen 注入)
    final provider = context.watch<GameProvider>();

    return GestureDetector(
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
          child: Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: CyberColors.cardBackground,
              borderRadius: BorderRadius.circular(32.0), // 对齐旧版的大圆角
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
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              itemCount: 16,
              itemBuilder: (context, index) {
                final r = index ~/ 4;
                final c = index % 4;
                // 注意：这里不再传入简单的 int, 以便 TileWidget 能在未来实现更复杂的 ID 动画
                return TileWidget(value: provider.grid[r][c]);
              },
            ),
          ),
        ),
      ),
    );
  }
}
