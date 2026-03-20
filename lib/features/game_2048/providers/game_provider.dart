import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/features/audio/services/sfx_service.dart';
import 'package:yueyou/features/game_2048/domain/tile_model.dart';

/// 移动方向枚举 (映射 JS L149-152)
enum Direction { up, down, left, right }

/// 2048 游戏逻辑的核心 Provider (ChangeNotifier)
/// 溯源：完整复刻自旧版 yueyou-app/www/js/modules/GameEngine.js
class GameProvider extends ChangeNotifier {
  // 棋盘大小 (溯源：JS L16)
  final int size = 4;

  // 4x4 棋盘 (溯源：JS L28-31)
  // 虽然 UI 现在用 grid, 但为了未来动画效果，我们保留 TileModel 对象的 board
  List<List<TileModel?>> board = [];

  // 兼容层：对齐旧版 UI 的 List<List<int>> 接口
  List<List<int>> get grid {
    return List.generate(
        size, (r) => List.generate(size, (c) => board[r][c]?.value ?? 0));
  }

  // 游戏实时分 (溯源：JS L17)
  int score = 0;

  // 最佳得分 (溯源：JS L10)
  int bestScore = 0;

  // 实时 Combo (溯源：JS L18)
  int combo = 0;

  // 最大 Combo (溯源：JS L11)
  int maxCombo = 0;

  // 下一个产生的方块 ID (溯源：JS L19)
  int _nextId = DateTime.now().millisecondsSinceEpoch;

  // 游戏是否结束 (溯源：JS L20)
  bool isOver = false;

  // 随机数生成器 (替换 JS Math.random)
  final Random _random = Random();

  /// 是否开启音效（由 SettingsProvider 通过 main.dart 同步注入）
  bool soundEnabled = true;

  GameProvider() {
    _loadSavedState();
  }

  /// App 启动时从 StorageService 恢复游戏快照（对应 JS loadSavedState）
  void _loadSavedState() {
    bestScore = StorageService.loadBestScore();
    maxCombo = StorageService.loadMaxCombo();
    final saved = StorageService.loadGameState();
    if (saved != null) {
      try {
        final boardRaw = saved['board_data'] as String?;
        if (boardRaw != null) {
          {
            final List<dynamic> rows = List<dynamic>.from(
                (boardRaw.isNotEmpty ? jsonDecode(boardRaw) : null) ?? []);
            if (rows.length == size) {
              board = List.generate(size, (r) {
                final row = rows[r] as List<dynamic>;
                return List.generate(size, (c) {
                  final cell = row[c];
                  if (cell == null) return null;
                  final m = cell as Map<String, dynamic>;
                  return TileModel(
                    id: (m['id'] as num).toInt(),
                    value: (m['value'] as num).toInt(),
                  );
                });
              });
              score = (saved['score'] as num?)?.toInt() ?? 0;
              combo = (saved['combo'] as num?)?.toInt() ?? 0;
              bestScore = (saved['bestScore'] as num?)?.toInt() ?? bestScore;
              maxCombo = (saved['maxCombo'] as num?)?.toInt() ?? maxCombo;
              int maxId = 0;
              for (final row in board) {
                for (final tile in row) {
                  if (tile != null && tile.id > maxId) maxId = tile.id;
                }
              }
              _nextId = maxId + 1;
              notifyListeners();
              return;
            }
          }
        }
      } catch (e) {
        debugPrint('GameProvider._loadSavedState error: $e');
      }
    }
    // 无存档或解析失败则新开一局
    _initFresh();
  }

  void _initFresh() {
    isOver = false;
    score = 0;
    combo = 0;
    board = List.generate(size, (_) => List.filled(size, null));
    addRandomTile();
    addRandomTile();
    updateScore();
    notifyListeners();
  }

  /// 初始化/重置游戏
  /// 溯源：映射 JS L15-26 (reset)
  void reset() {
    isOver = false;
    score = 0;
    combo = 0;
    board = List.generate(size, (_) => List.filled(size, null));
    addRandomTile();
    addRandomTile();
    updateScore();
    _persistState();
    notifyListeners();
  }

  /// 执行移动逻辑 (核心迁移逻辑)
  /// 溯源：映射 JS L32-112 (move)
  void move(Direction direction) {
    if (isOver) return;

    bool moved = false;
    // 记录是否有任何合并发生，用于维护 combo
    List<Map<String, dynamic>> mergedTiles = [];

    // 触发滑动音效（轻量级触觉反馈）
    if (soundEnabled) {
      SfxService.playMerge();
    }

    // 获取移动向量 (溯源：JS L147-154)
    final vector = _getVector(direction);
    // 获取遍历顺序 (溯源：JS L155-161)
    final traversal = _getTraversalOrder(vector);

    // 记录本轮是否已经合并过的标记矩阵 (溯源：JS L46-48)
    List<List<bool>> mergedFlags =
        List.generate(size, (_) => List.filled(size, false));

    // 开始遍历
    for (int r in traversal['rows']!) {
      for (int c in traversal['cols']!) {
        TileModel? tile = board[r][c];
        if (tile == null) continue;

        // 查找最远的可移动位置 (溯源：JS L54-60)
        int curR = r;
        int curC = c;
        int nextR = r + vector['y']!;
        int nextC = c + vector['x']!;

        // 循环推移 (溯源：JS L56-62)
        while (_inBounds(nextR, nextC) && board[nextR][nextC] == null) {
          board[nextR][nextC] = tile;
          board[curR][curC] = null;

          curR = nextR;
          curC = nextC;
          nextR = curR + vector['y']!;
          nextC = curC + vector['x']!;
          moved = true; // 发生了位移
        }

        // 检查合并 (溯源：JS L63-82)
        if (_inBounds(nextR, nextC)) {
          TileModel? targetTile = board[nextR][nextC];
          // 逻辑：值相等且目标位置未在本轮合并过 (JS L65)
          if (targetTile != null &&
              targetTile.value == tile.value &&
              !mergedFlags[nextR][nextC]) {
            // 合并操作：值 * 2 (溯源：JS L66)
            board[nextR][nextC] =
                targetTile.copyWith(value: targetTile.value * 2);
            board[curR][curC] = null;

            // 标记已合并，并更新状态
            mergedFlags[nextR][nextC] = true;
            moved = true;
            combo++; // (溯源：JS L70)

            // 更新最大 Combo (溯源：JS L71-74)
            if (combo > maxCombo) {
              maxCombo = combo;
            }

            // 存入合并列表（在 JS 里用于触发 3D 效果，此处预留）
            mergedTiles.add(
                {'r': nextR, 'c': nextC, 'value': board[nextR][nextC]!.value});
          }
        }
      }
    }

    if (moved) {
      // 没有任何合并时 combo 归零 (溯源：JS L87)
      if (mergedTiles.isEmpty) {
        combo = 0;
      }

      // 添加新的随机块 (溯源：JS L89)
      addRandomTile();
      // 更新全盘总分 (溯源：JS L90)
      updateScore();

      // 判断是否无路可走 (溯源：JS L91)
      if (!_movesAvailable()) {
        isOver = true;
      }

      // 合并音效（对应 JS: if (result.mergedTiles.length > 0 && t.sound) l.playEffect('merge')）
      if (mergedTiles.isNotEmpty && soundEnabled) {
        SfxService.playMerge();
      }
      _persistState();
      notifyListeners();
    }
  }

  /// 全盘得分计算逻辑
  /// 🚨 指令：严禁使用标准 2048 的“累加得分法”，必须严格遵循旧版的“全盘求和法”
  /// 溯源：映射 JS L113-119 (updateScore)
  void updateScore() {
    int total = 0;
    for (int r = 0; r < size; r++) {
      for (int c = 0; c < size; c++) {
        if (board[r][c] != null) {
          total += board[r][c]!.value;
        }
      }
    }
    score = total;

    // 记录最佳分数 (溯源：JS L130-132)
    if (score > bestScore) {
      bestScore = score;
    }
  }

  /// 持久化当前快照到 StorageService（对应 JS saveLocalState）
  void _persistState() {
    final boardJson = List.generate(
        size,
        (r) => List.generate(size, (c) {
              final t = board[r][c];
              if (t == null) return null;
              return <String, dynamic>{'id': t.id, 'value': t.value};
            }));
    final int novelIndex = StorageService.getCurrentNovelIndex();
    final String? currentNovelId = StorageService.getCurrentNovelId();
    StorageService.saveGameState(
      board: boardJson,
      score: score,
      combo: combo,
      bestScore: bestScore,
      maxCombo: maxCombo,
      novelIndex: novelIndex,
      currentNovelId: currentNovelId,
    );
  }

  /// 导出当前棋盘 JSON（用于云同步）
  String exportBoardDataJson() {
    final boardJson = List.generate(
        size,
        (r) => List.generate(size, (c) {
              final t = board[r][c];
              if (t == null) return null;
              return <String, dynamic>{'id': t.id, 'value': t.value};
            }));
    return jsonEncode(boardJson);
  }

  /// 云端拉取后的状态灌入
  void applyRemoteState({
    required String boardData,
    required int score,
    int? novelIndex,
    int? currentNovelId,
  }) {
    try {
      final List<dynamic> rows = List<dynamic>.from(
          (boardData.isNotEmpty ? jsonDecode(boardData) : null) ?? []);
      if (rows.length != size) {
        return;
      }
      board = List.generate(size, (r) {
        final row = rows[r] as List<dynamic>;
        return List.generate(size, (c) {
          final cell = row[c];
          if (cell == null) return null;
          final m = cell as Map<String, dynamic>;
          return TileModel(
            id: (m['id'] as num).toInt(),
            value: (m['value'] as num).toInt(),
          );
        });
      });
      this.score = score;
      if (score > bestScore) {
        bestScore = score;
      }
      int maxId = 0;
      for (final row in board) {
        for (final tile in row) {
          if (tile != null && tile.id > maxId) maxId = tile.id;
        }
      }
      _nextId = maxId + 1;

      StorageService.saveGameState(
        board: List.generate(
            size,
            (r) => List.generate(size, (c) {
                  final t = board[r][c];
                  if (t == null) return null;
                  return <String, dynamic>{'id': t.id, 'value': t.value};
                })),
        score: this.score,
        combo: combo,
        bestScore: bestScore,
        maxCombo: maxCombo,
        novelIndex: novelIndex ?? StorageService.getCurrentNovelIndex(),
        currentNovelId: currentNovelId != null
            ? currentNovelId.toString()
            : StorageService.getCurrentNovelId(),
      );
      notifyListeners();
    } catch (e) {
      debugPrint('GameProvider.applyRemoteState error: $e');
    }
  }

  /// 在空格处添加随机块 (2 或 4)
  /// 溯源：映射 JS L179-191 (addRandomTile)
  void addRandomTile() {
    List<Map<String, int>> emptyCells = [];
    for (int r = 0; r < size; r++) {
      for (int c = 0; c < size; c++) {
        if (board[r][c] == null) {
          emptyCells.add({'r': r, 'c': c});
        }
      }
    }

    if (emptyCells.isNotEmpty) {
      final cell = emptyCells[_random.nextInt(emptyCells.length)];
      // 生成概率：2 (90%), 4 (10%) (溯源：JS L188)
      int value = _random.nextDouble() < 0.9 ? 2 : 4;
      board[cell['r']!][cell['c']!] = TileModel(id: _nextId++, value: value);
    }
  }

  /// 检查边界 (溯源：JS L144-146)
  bool _inBounds(int r, int c) {
    return r >= 0 && r < size && c >= 0 && c < size;
  }

  /// 移动向量映射 (溯源：JS L147-154)
  Map<String, int> _getVector(Direction dir) {
    switch (dir) {
      case Direction.up:
        return {'x': 0, 'y': -1};
      case Direction.down:
        return {'x': 0, 'y': 1};
      case Direction.left:
        return {'x': -1, 'y': 0};
      case Direction.right:
        return {'x': 1, 'y': 0};
    }
  }

  /// 遍历顺序映射 (溯源：JS L155-161)
  Map<String, List<int>> _getTraversalOrder(Map<String, int> vector) {
    List<int> rows = List.generate(size, (i) => i);
    List<int> cols = List.generate(size, (i) => i);

    // 如果是向下，则行序反转 (JS L158)
    if (vector['y'] == 1) rows = rows.reversed.toList();
    // 如果是向右，则列序反转 (JS L159)
    if (vector['x'] == 1) cols = cols.reversed.toList();

    return {'rows': rows, 'cols': cols};
  }

  /// 判定是否还有可行的移动 (溯源：JS L162-178)
  bool _movesAvailable() {
    for (int r = 0; r < size; r++) {
      for (int c = 0; c < size; c++) {
        // 如果有空位，可用
        if (board[r][c] == null) return true;

        // 检查四个方向 (溯源：JS L166-175)
        for (var dir in Direction.values) {
          final vector = _getVector(dir);
          final nextR = r + vector['y']!;
          final nextC = c + vector['x']!;

          if (_inBounds(nextR, nextC)) {
            final target = board[nextR][nextC];
            // 如果目标是空位或值相等，则仍有移动空间
            if (target == null || target.value == board[r][c]!.value) {
              return true;
            }
          }
        }
      }
    }
    return false;
  }
}
