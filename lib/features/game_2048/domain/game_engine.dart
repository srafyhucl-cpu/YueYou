import 'tile_model.dart';

/// 2048 的移动方向。
enum Direction { up, down, left, right }

/// 2048 领域状态，只包含棋盘与游戏规则所需数据。
class GameState {
  final List<List<TileModel?>> board;
  final int score;
  final int bestScore;
  final int combo;
  final int maxCombo;
  final bool isOver;

  GameState({
    required List<List<TileModel?>> board,
    this.score = 0,
    this.bestScore = 0,
    this.combo = 0,
    this.maxCombo = 0,
    this.isOver = false,
  }) : board = _copyGameBoard(board);

  /// 生成只修改指定字段的新状态，避免领域算法原地改变输入。
  GameState copyWith({
    List<List<TileModel?>>? board,
    int? score,
    int? bestScore,
    int? combo,
    int? maxCombo,
    bool? isOver,
  }) {
    return GameState(
      board: board ?? this.board,
      score: score ?? this.score,
      bestScore: bestScore ?? this.bestScore,
      combo: combo ?? this.combo,
      maxCombo: maxCombo ?? this.maxCombo,
      isOver: isOver ?? this.isOver,
    );
  }
}

/// 2048 棋盘、移动、合并、计分和结束判断的纯 Dart 内核。
class GameEngine {
  static const int size = 4;

  const GameEngine();

  /// 执行移动。随机出生块由上层选择后通过 [addTile] 写入结果状态。
  ({
    GameState state,
    bool moved,
    int lastMergedValue,
    bool lastMoveNoMerge,
  }) move(GameState current, Direction direction) {
    if (current.isOver) {
      return (
        state: current,
        moved: false,
        lastMergedValue: 0,
        lastMoveNoMerge: false,
      );
    }

    final nextBoard = _copyGameBoard(current.board);
    final vector = _vectorFor(direction);
    final traversal = _traversalFor(vector);
    final mergedFlags = List.generate(
      size,
      (_) => List<bool>.filled(size, false),
    );
    var moved = false;
    var combo = current.combo;
    var maxCombo = current.maxCombo;
    final mergedValues = <int>[];

    // 按远离移动方向到靠近移动方向遍历，保证连续合并顺序稳定。
    for (final row in traversal.rows) {
      for (final column in traversal.columns) {
        final tile = nextBoard[row][column];
        if (tile == null) continue;

        var currentRow = row;
        var currentColumn = column;
        var nextRow = currentRow + vector.rowDelta;
        var nextColumn = currentColumn + vector.columnDelta;

        // 先把方块推到移动方向上最远的空位。
        while (_inBounds(nextRow, nextColumn) &&
            nextBoard[nextRow][nextColumn] == null) {
          nextBoard[nextRow][nextColumn] = tile;
          nextBoard[currentRow][currentColumn] = null;
          currentRow = nextRow;
          currentColumn = nextColumn;
          nextRow = currentRow + vector.rowDelta;
          nextColumn = currentColumn + vector.columnDelta;
          moved = true;
        }

        // 相同数值且目标本轮尚未合并时才允许合并一次。
        if (_inBounds(nextRow, nextColumn)) {
          final target = nextBoard[nextRow][nextColumn];
          if (target != null &&
              target.value == tile.value &&
              !mergedFlags[nextRow][nextColumn]) {
            final mergedValue = target.value * 2;
            nextBoard[nextRow][nextColumn] =
                target.copyWith(value: mergedValue);
            nextBoard[currentRow][currentColumn] = null;
            mergedFlags[nextRow][nextColumn] = true;
            moved = true;
            combo++;
            if (combo > maxCombo) maxCombo = combo;
            mergedValues.add(mergedValue);
          }
        }
      }
    }

    if (!moved) {
      final blocked = !_movesAvailable(nextBoard);
      return (
        state: current.copyWith(isOver: blocked),
        moved: false,
        lastMergedValue: 0,
        lastMoveNoMerge: false,
      );
    }

    if (mergedValues.isEmpty) combo = 0;
    final score = _scoreOf(nextBoard);
    final nextState = current.copyWith(
      board: nextBoard,
      score: score,
      bestScore: score > current.bestScore ? score : current.bestScore,
      combo: combo,
      maxCombo: maxCombo,
      isOver: !_movesAvailable(nextBoard),
    );
    return (
      state: nextState,
      moved: true,
      lastMergedValue: mergedValues.isEmpty ? 0 : _max(mergedValues),
      lastMoveNoMerge: mergedValues.isEmpty,
    );
  }

  /// 在指定空位添加由编排层生成的方块，并重新判断结束状态。
  GameState addTile(GameState current, int row, int column, TileModel tile) {
    if (!_inBounds(row, column) || current.board[row][column] != null) {
      return current;
    }
    final board = _copyGameBoard(current.board);
    board[row][column] = tile;
    final score = _scoreOf(board);
    return current.copyWith(
      board: board,
      score: score,
      bestScore: score > current.bestScore ? score : current.bestScore,
      isOver: !_movesAvailable(board),
    );
  }

  /// 移除指定方块，供游戏彩蛋使用。
  GameState removeTile(GameState current, int id) {
    final board = _copyGameBoard(current.board);
    for (var row = 0; row < size; row++) {
      for (var column = 0; column < size; column++) {
        if (board[row][column]?.id == id) {
          board[row][column] = null;
          final score = _scoreOf(board);
          return current.copyWith(
            board: board,
            score: score,
            bestScore: score > current.bestScore ? score : current.bestScore,
            isOver: !_movesAvailable(board),
          );
        }
      }
    }
    return current;
  }

  /// 返回所有空位，随机选择由 Provider 完成。
  List<({int row, int column})> emptyCells(GameState state) {
    final cells = <({int row, int column})>[];
    for (var row = 0; row < size; row++) {
      for (var column = 0; column < size; column++) {
        if (state.board[row][column] == null) {
          cells.add((row: row, column: column));
        }
      }
    }
    return cells;
  }

  int scoreOf(GameState state) => _scoreOf(state.board);

  bool movesAvailable(GameState state) => _movesAvailable(state.board);

  static _Vector _vectorFor(Direction direction) {
    return switch (direction) {
      Direction.up => const _Vector(rowDelta: -1, columnDelta: 0),
      Direction.down => const _Vector(rowDelta: 1, columnDelta: 0),
      Direction.left => const _Vector(rowDelta: 0, columnDelta: -1),
      Direction.right => const _Vector(rowDelta: 0, columnDelta: 1),
    };
  }

  static _Traversal _traversalFor(_Vector vector) {
    final baseRows = List<int>.generate(size, (index) => index);
    final baseColumns = List<int>.generate(size, (index) => index);
    final rows = vector.rowDelta == 1 ? baseRows.reversed.toList() : baseRows;
    final columns =
        vector.columnDelta == 1 ? baseColumns.reversed.toList() : baseColumns;
    return _Traversal(rows: rows, columns: columns);
  }

  static bool _inBounds(int row, int column) {
    return row >= 0 && row < size && column >= 0 && column < size;
  }

  static bool _movesAvailable(List<List<TileModel?>> board) {
    for (var row = 0; row < size; row++) {
      for (var column = 0; column < size; column++) {
        if (board[row][column] == null) return true;
        for (final direction in Direction.values) {
          final vector = _vectorFor(direction);
          final nextRow = row + vector.rowDelta;
          final nextColumn = column + vector.columnDelta;
          if (_inBounds(nextRow, nextColumn) &&
              board[nextRow][nextColumn]?.value == board[row][column]!.value) {
            return true;
          }
        }
      }
    }
    return false;
  }

  static int _scoreOf(List<List<TileModel?>> board) {
    var score = 0;
    for (final row in board) {
      for (final tile in row) {
        if (tile != null) score += tile.value;
      }
    }
    return score;
  }

  static int _max(List<int> values) {
    var result = values.first;
    for (final value in values.skip(1)) {
      if (value > result) result = value;
    }
    return result;
  }
}

List<List<TileModel?>> _copyGameBoard(List<List<TileModel?>> board) {
  if (board.length != GameEngine.size ||
      board.any((row) => row.length != GameEngine.size)) {
    throw ArgumentError('2048 棋盘必须是 4x4 矩阵');
  }
  return board.map((row) => List<TileModel?>.of(row)).toList();
}

class _Vector {
  final int rowDelta;
  final int columnDelta;

  const _Vector({required this.rowDelta, required this.columnDelta});
}

class _Traversal {
  final List<int> rows;
  final List<int> columns;

  const _Traversal({required this.rows, required this.columns});
}
