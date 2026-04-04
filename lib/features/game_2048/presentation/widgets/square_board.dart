import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:yueyou/core/theme/cyber_colors.dart';
import 'package:yueyou/core/theme/cyber_dimensions.dart';
import 'package:yueyou/core/theme/cyber_shadows.dart';
import 'package:yueyou/features/game_2048/providers/game_provider.dart';
import 'package:yueyou/features/game_2048/domain/tile_model.dart';
import 'tile_widget.dart';
import 'board_reset_animation.dart';
import 'rain_effect.dart';

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
  bool _showGameOverDialog = false;
  late AnimationController _tiltController;
  late Animation<double> _tiltX;
  late Animation<double> _tiltY;
  GameProvider? _provider;
  StreamSubscription<void>? _gameOverSubscription;

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

  Color _tileValueColor(int value) {
    switch (value) {
      case 2:
        return CyberColors.tile2End;
      case 4:
        return CyberColors.tile4End;
      case 8:
        return CyberColors.tile8End;
      case 16:
        return CyberColors.tile16End;
      case 32:
        return CyberColors.tile32End;
      case 64:
        return CyberColors.tile64End;
      case 128:
        return CyberColors.tile128Start;
      case 256:
        return CyberColors.tile256Start;
      case 512:
        return CyberColors.tile512;
      case 1024:
        return CyberColors.tile1024Start;
      case 2048:
        return CyberColors.tile2048End;
      default:
        return CyberColors.neonCyan;
    }
  }

  /// 计算局面评级（基于最大棋子）
  String _calculateRating(int maxTile) {
    if (maxTile >= 2048) return '传奇';
    if (maxTile >= 1024) return '大师';
    if (maxTile >= 512) return '专家';
    if (maxTile >= 256) return '熟练';
    if (maxTile >= 128) return '进阶';
    return '入门';
  }

  /// 获取评级颜色
  Color _ratingColor(String rating) {
    switch (rating) {
      case '传奇':
        return CyberColors.tileGold; // 金色
      case '大师':
        return CyberColors.neonPink;
      case '专家':
        return CyberColors.tile512;
      case '熟练':
        return CyberColors.tile256Start;
      case '进阶':
        return CyberColors.tile128Start;
      default:
        return CyberColors.whiteMedium;
    }
  }

  /// 生成战绩文案
  String _generateShareText({
    required DateTime endTime,
    required int score,
    required int maxTile,
    required int maxCombo,
    required String rating,
  }) {
    final timeStr =
        '${endTime.month.toString().padLeft(2, '0')}-${endTime.day.toString().padLeft(2, '0')} '
        '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';
    return '阅游2048 战报\n'
        '时间：$timeStr\n'
        '评级：$rating\n'
        '得分：$score\n'
        '最大棋子：$maxTile\n'
        '最高连击：$maxCombo\n'
        '—— 快来挑战我吧！——';
  }

  /// 复制战绩到剪贴板
  Future<void> _copyToClipboard(String text, BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '战绩已复制到剪贴板',
            style: TextStyle(
              color: CyberColors.whiteHigh,
              fontSize: 14,
            ),
          ),
          backgroundColor: CyberColors.surface,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildGameOverStatItem({
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Container(
      width: 80,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: CyberColors.surface.withOpacity(0.48),
        borderRadius: BorderRadius.circular(CyberDimensions.radiusS),
        border: Border.all(
          color: CyberColors.neonCyan.withOpacity(0.2),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CyberColors.whiteMuted.withOpacity(0.9),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor ?? CyberColors.whiteHigh,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _gameOverSubscription?.cancel();
    if (_tiltController.isAnimating) {
      _tiltController.stop();
    }
    _tiltController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<GameProvider>();
    if (!identical(_provider, provider)) {
      _gameOverSubscription?.cancel();
      _provider = provider;
      _showGameOverDialog = provider.isOver;
      _gameOverSubscription = provider.onGameOver.listen((_) {
        if (!mounted) return;
        setState(() {
          _showGameOverDialog = true;
        });
      });
    }
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
                  const padding = 20.0;
                  const spacing = 12.0;
                  final cellSize = (boardSize - padding * 2 - spacing * 3) / 4;

                  return Selector<GameProvider, List<List<TileModel?>>>(
                    selector: (context, provider) => provider.board,
                    builder: (context, board, _) {
                      var maxTile = 0;
                      for (final row in board) {
                        for (final tile in row) {
                          if (tile == null) continue;
                          if (tile.value > maxTile) {
                            maxTile = tile.value;
                          }
                        }
                      }

                      // 游戏结束时间戳
                      final endTime = DateTime.now();
                      // 局面评级
                      final rating = _calculateRating(maxTile);
                      final ratingColor = _ratingColor(rating);

                      return Container(
                        clipBehavior: Clip.none,
                        decoration: BoxDecoration(
                          color: CyberColors.background.withOpacity(0.75),
                          borderRadius:
                              BorderRadius.circular(CyberDimensions.radiusXL),
                          border: Border.all(
                            color: CyberColors.neonCyan.withOpacity(0.4),
                            width: CyberDimensions.borderThick,
                          ),
                          boxShadow: [
                            ...CyberShadows.elevated,
                            BoxShadow(
                              color: CyberColors.neonCyan.withOpacity(0.12),
                              blurRadius: 16,
                              spreadRadius: -4,
                              offset: const Offset(0, 0),
                            ),
                          ],
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(padding),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  _buildBackgroundGrid(cellSize, spacing),
                                  ...board
                                      .expand((row) => row)
                                      .where((tile) => tile != null)
                                      .map((tile) {
                                    final pos = _findTilePosition(board, tile!);
                                    return AnimatedPositioned(
                                      key: ValueKey(tile.id),
                                      duration:
                                          const Duration(milliseconds: 150),
                                      curve: Curves.easeOut,
                                      left: pos.$2 * (cellSize + spacing),
                                      top: pos.$1 * (cellSize + spacing),
                                      width: cellSize,
                                      height: cellSize,
                                      child: TileWidget(
                                        id: tile.id,
                                        value: tile.value,
                                        onEliminate: () {
                                          context
                                              .read<GameProvider>()
                                              .eliminateTileById(tile.id);
                                        },
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                            if (_showGameOverDialog)
                              Positioned.fill(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    CyberDimensions.radiusXL,
                                  ),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(
                                      sigmaX: CyberDimensions.blurLight,
                                      sigmaY: CyberDimensions.blurLight,
                                    ),
                                    child: Container(
                                      color: CyberColors.blackOverlay
                                          .withOpacity(0.78),
                                      padding: const EdgeInsets.all(12),
                                      child: LayoutBuilder(
                                        builder: (context, overlayConstraints) {
                                          return Center(
                                            child: ConstrainedBox(
                                              constraints: BoxConstraints(
                                                maxWidth: 360,
                                                maxHeight: overlayConstraints
                                                        .maxHeight *
                                                    0.9,
                                              ),
                                              child: Stack(
                                                children: [
                                                  // 下雨特效层
                                                  const Positioned.fill(
                                                    child: RainEffect(
                                                      rainCount: 20,
                                                    ),
                                                  ),
                                                  // 弹窗内容层
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            12),
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        begin:
                                                            Alignment.topLeft,
                                                        end: Alignment
                                                            .bottomRight,
                                                        colors: [
                                                          CyberColors
                                                              .whiteFaint,
                                                          CyberColors.whiteFaint
                                                              .withOpacity(
                                                                  0.03),
                                                        ],
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        CyberDimensions.radiusL,
                                                      ),
                                                      border: Border.all(
                                                        color: CyberColors
                                                            .neonCyan
                                                            .withOpacity(0.2),
                                                        width: 1.6,
                                                      ),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: CyberColors
                                                              .neonCyan
                                                              .withOpacity(0.1),
                                                          blurRadius: 12,
                                                          spreadRadius: 0,
                                                        ),
                                                      ],
                                                    ),
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          '游戏结束',
                                                          style: TextStyle(
                                                            color: CyberColors
                                                                .neonPink,
                                                            fontSize: 24,
                                                            fontWeight:
                                                                FontWeight.w900,
                                                            letterSpacing: 1.0,
                                                            shadows: [
                                                              Shadow(
                                                                color: CyberColors
                                                                    .neonPink
                                                                    .withOpacity(
                                                                        0.55),
                                                                blurRadius: 16,
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            height: 4),
                                                        const Text(
                                                          '本局已无可移动棋子，是否重新开局？',
                                                          style: TextStyle(
                                                            color: CyberColors
                                                                .whiteHigh,
                                                            fontSize: 11,
                                                            letterSpacing: 0.5,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            height: 8),
                                                        // 时间戳 + 评级（合并为一行）
                                                        Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            Text(
                                                              '${endTime.month.toString().padLeft(2, '0')}-${endTime.day.toString().padLeft(2, '0')} ${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
                                                              style:
                                                                  const TextStyle(
                                                                color: CyberColors
                                                                    .whiteMuted,
                                                                fontSize: 10,
                                                                letterSpacing:
                                                                    0.3,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                width: 8),
                                                            Container(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                horizontal: 8,
                                                                vertical: 2,
                                                              ),
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: ratingColor
                                                                    .withOpacity(
                                                                        0.2),
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            6),
                                                                border:
                                                                    Border.all(
                                                                  color: ratingColor
                                                                      .withOpacity(
                                                                          0.5),
                                                                  width: 0.8,
                                                                ),
                                                              ),
                                                              child: Text(
                                                                rating,
                                                                style:
                                                                    TextStyle(
                                                                  color:
                                                                      ratingColor,
                                                                  fontSize: 10,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                            height: 8),
                                                        Wrap(
                                                          spacing: 8,
                                                          runSpacing: 6,
                                                          alignment:
                                                              WrapAlignment
                                                                  .center,
                                                          children: [
                                                            _buildGameOverStatItem(
                                                              label: '得分',
                                                              value: provider
                                                                  .score
                                                                  .toString(),
                                                              valueColor:
                                                                  CyberColors
                                                                      .neonCyan,
                                                            ),
                                                            _buildGameOverStatItem(
                                                              label: '最大棋子',
                                                              value: maxTile ==
                                                                      0
                                                                  ? '-'
                                                                  : maxTile
                                                                      .toString(),
                                                              valueColor: maxTile ==
                                                                      0
                                                                  ? CyberColors
                                                                      .whiteHigh
                                                                  : _tileValueColor(
                                                                      maxTile),
                                                            ),
                                                            _buildGameOverStatItem(
                                                              label: '最大连击',
                                                              value: provider
                                                                  .maxCombo
                                                                  .toString(),
                                                              valueColor:
                                                                  CyberColors
                                                                      .neonPink,
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                            height: 8),
                                                        // 按钮区域（横向排列）
                                                        Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            OutlinedButton.icon(
                                                              onPressed: () {
                                                                final shareText =
                                                                    _generateShareText(
                                                                  endTime:
                                                                      endTime,
                                                                  score: provider
                                                                      .score,
                                                                  maxTile:
                                                                      maxTile,
                                                                  maxCombo: provider
                                                                      .maxCombo,
                                                                  rating:
                                                                      rating,
                                                                );
                                                                _copyToClipboard(
                                                                    shareText,
                                                                    context);
                                                              },
                                                              icon: const Icon(
                                                                Icons.copy,
                                                                size: 12,
                                                                color: CyberColors
                                                                    .neonGreen,
                                                              ),
                                                              label: const Text(
                                                                '复制',
                                                                style:
                                                                    TextStyle(
                                                                  color: CyberColors
                                                                      .neonGreen,
                                                                  fontSize: 11,
                                                                ),
                                                              ),
                                                              style:
                                                                  OutlinedButton
                                                                      .styleFrom(
                                                                foregroundColor:
                                                                    CyberColors
                                                                        .neonGreen,
                                                                side:
                                                                    BorderSide(
                                                                  color: CyberColors
                                                                      .neonGreen
                                                                      .withOpacity(
                                                                          0.5),
                                                                  width: 1,
                                                                ),
                                                                padding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                  horizontal:
                                                                      10,
                                                                  vertical: 8,
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                width: 8),
                                                            OutlinedButton(
                                                              onPressed: () {
                                                                setState(() {
                                                                  _showGameOverDialog =
                                                                      false;
                                                                });
                                                              },
                                                              style:
                                                                  OutlinedButton
                                                                      .styleFrom(
                                                                foregroundColor:
                                                                    CyberColors
                                                                        .whiteMedium,
                                                                backgroundColor:
                                                                    CyberColors
                                                                        .whiteFaint,
                                                                side:
                                                                    BorderSide(
                                                                  color: CyberColors
                                                                      .whiteMedium
                                                                      .withOpacity(
                                                                          0.6),
                                                                  width: 1,
                                                                ),
                                                                padding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                  horizontal:
                                                                      12,
                                                                  vertical: 8,
                                                                ),
                                                              ),
                                                              child: const Text(
                                                                '取消',
                                                                style:
                                                                    TextStyle(
                                                                  fontSize: 11,
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                width: 8),
                                                            ElevatedButton(
                                                              onPressed: () {
                                                                setState(() {
                                                                  _showGameOverDialog =
                                                                      false;
                                                                });
                                                                context
                                                                    .read<
                                                                        GameProvider>()
                                                                    .reset();
                                                              },
                                                              style:
                                                                  ElevatedButton
                                                                      .styleFrom(
                                                                backgroundColor:
                                                                    CyberColors
                                                                        .neonCyan,
                                                                foregroundColor:
                                                                    CyberColors
                                                                        .background,
                                                                padding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                  horizontal:
                                                                      14,
                                                                  vertical: 8,
                                                                ),
                                                              ),
                                                              child: const Text(
                                                                '重新开始',
                                                                style:
                                                                    TextStyle(
                                                                  fontSize: 11,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
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
    return SizedBox(
      width: cellSize * 4 + spacing * 3,
      height: cellSize * 4 + spacing * 3,
      child: Stack(
        clipBehavior: Clip.none,
        children: List.generate(16, (index) {
          final row = index ~/ 4;
          final col = index % 4;
          return Positioned(
            left: col * (cellSize + spacing),
            top: row * (cellSize + spacing),
            width: cellSize,
            height: cellSize,
            child: Container(
              decoration: BoxDecoration(
                color: CyberColors.surface.withOpacity(0.4),
                borderRadius: BorderRadius.circular(CyberDimensions.radiusM),
              ),
            ),
          );
        }),
      ),
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
