import 'dart:math';

/// 2048 游戏移动方向枚举
enum Direction { up, down, left, right }

/// 2048 游戏核心领域逻辑类 (纯 Dart 实现)
/// 专注于矩阵运算、合并算法与分数管理，严禁引入 UI 依赖
class GameLogic {
  // 4x4 棋盘矩阵（0 表示空位）
  List<List<int>> grid = List.generate(4, (_) => List.filled(4, 0));

  // 当前总分
  int score = 0;

  // 随机数生成器
  final Random _random = Random();

  /// 初始化游戏
  /// 清空棋盘并随机生成两个初始方块
  void initGame() {
    grid = List.generate(4, (_) => List.filled(4, 0));
    score = 0;
    _addRandomTile();
    _addRandomTile();
  }

  /// 核心移动方法
  /// 返回布尔值：表示该方向的移动是否有效（是否有方块发生了位移或合并）
  bool move(Direction dir) {
    bool changed = false;

    // 根据方向对每一行/列进行独立处理
    if (dir == Direction.left || dir == Direction.right) {
      for (int i = 0; i < 4; i++) {
        List<int> row = List.from(grid[i]);
        if (dir == Direction.right) row = row.reversed.toList();

        List<int> newRow = _processLine(row);

        if (dir == Direction.right) newRow = newRow.reversed.toList();

        if (!_listsEqual(grid[i], newRow)) {
          grid[i] = newRow;
          changed = true;
        }
      }
    } else {
      for (int j = 0; j < 4; j++) {
        List<int> column = [grid[0][j], grid[1][j], grid[2][j], grid[3][j]];
        if (dir == Direction.down) column = column.reversed.toList();

        List<int> newColumn = _processLine(column);

        if (dir == Direction.down) newColumn = newColumn.reversed.toList();

        for (int i = 0; i < 4; i++) {
          if (grid[i][j] != newColumn[i]) {
            grid[i][j] = newColumn[i];
            changed = true;
          }
        }
      }
    }

    // 如果发生了有效移动，则生成一个新方块
    if (changed) {
      _addRandomTile();
    }

    return changed;
  }

  /// 处理单行/单列的合并逻辑（统一抽象为向左压实合并）
  /// 算法步骤：1. 去零 2. 合并相同项 3. 再次去零补齐
  List<int> _processLine(List<int> line) {
    // 1. 去除所有零元素（压实）
    List<int> nonZeros = line.where((x) => x != 0).toList();

    // 2. 合并相邻且相同的数字
    for (int i = 0; i < nonZeros.length - 1; i++) {
      if (nonZeros[i] == nonZeros[i + 1]) {
        nonZeros[i] *= 2; // 数字翻倍
        score += nonZeros[i]; // 增加分数
        nonZeros[i + 1] = 0; // 标记待合并项
        i++; // 跳过已合并的项，防止“一次移动双重合并”
      }
    }

    // 3. 再次去零并补齐长度至 4
    List<int> result = nonZeros.where((x) => x != 0).toList();
    while (result.length < 4) {
      result.add(0);
    }
    return result;
  }

  /// 在随机空位生成一个新方块
  /// 生成概率：2 (90%), 4 (10%)
  void _addRandomTile() {
    List<Point<int>> emptyCells = [];
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        if (grid[i][j] == 0) {
          emptyCells.add(Point(i, j));
        }
      }
    }

    if (emptyCells.isNotEmpty) {
      final cell = emptyCells[_random.nextInt(emptyCells.length)];
      grid[cell.x][cell.y] = _random.nextDouble() < 0.9 ? 2 : 4;
    }
  }

  /// 判断游戏是否结束
  /// 结束条件：棋盘已满且无法再进行任何合并
  bool isGameOver() {
    // 1. 检查是否有空位
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        if (grid[i][j] == 0) return false;
      }
    }

    // 2. 检查横向和纵向是否有相邻且相同的数字
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        int current = grid[i][j];
        // 检查右侧
        if (j < 3 && current == grid[i][j + 1]) return false;
        // 检查下方
        if (i < 3 && current == grid[i + 1][j]) return false;
      }
    }

    return true; // 彻底锁死，游戏结束
  }

  /// 辅助工具：判断两组数据是否完全一致
  bool _listsEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
