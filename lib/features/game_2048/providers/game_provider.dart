import 'dart:async';
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
class GameProvider extends ChangeNotifier with WidgetsBindingObserver {
  // 棋盘大小 (溯源：JS L16)
  final int size = 4;

  // 4x4 棋盘 (溯源：JS L28-31)
  List<List<TileModel?>> _board = [];
  List<List<TileModel?>> get board => _board;

  // 兼容层：对齐旧版 UI 的 List<List<int>> 接口
  List<List<int>> get grid {
    return List.generate(
        size, (r) => List.generate(size, (c) => _board[r][c]?.value ?? 0));
  }

  // 游戏实时分 (溯源：JS L17)
  int _score = 0;
  int get score => _score;

  // 最佳得分 (溯源：JS L10)
  int _bestScore = 0;
  int get bestScore => _bestScore;

  // 实时 Combo (溯源：JS L18)
  int _combo = 0;
  int get combo => _combo;

  // 最大 Combo (溯源：JS L11)
  int _maxCombo = 0;
  int get maxCombo => _maxCombo;

  // 下一个产生的方块 ID (溯源：JS L19)
  int _nextId = DateTime.now().millisecondsSinceEpoch;

  // 游戏是否结束 (溯源：JS L20)
  bool _isOver = false;
  bool get isOver => _isOver;

  // 随机数生成器 (替换 JS Math.random，支持注入种子用于测试)
  late final Random _random;

  /// 是否开启音效（由 SettingsProvider 通过 main.dart 同步注入）
  bool _soundEnabled = true;
  bool get soundEnabled => _soundEnabled;
  set soundEnabled(bool value) {
    if (_soundEnabled != value) {
      _soundEnabled = value;
      notifyListeners();
    }
  }

  /// 上一次滑动方向（供吉祥物眼球跟随使用）
  Direction? _lastMoveDirection;
  Direction? get lastMoveDirection => _lastMoveDirection;

  /// 用户有效操作回调（由 main.dart 注入，用于重置 TTS 空闲计时器）
  void Function()? onUserMove;

  /// 本次移动中合并产生的最大値（0=无合并，供吉祥物欢呼判断）
  int _lastMergedValue = 0;
  int get lastMergedValue => _lastMergedValue;

  /// 本次有有效滑动但无任何合并（供吉祥物惋惜/生气表情）
  bool _lastMoveNoMerge = false;
  bool get lastMoveNoMerge => _lastMoveNoMerge;

  /// 音效服务（支持注入 mock，默认使用 SfxService）
  final void Function(int)? _onPlayMerge;
  Timer? _persistDebounceTimer;
  final Duration _persistDebounceDuration;
  final StreamController<void> _gameOverController =
      StreamController<void>.broadcast();

  Stream<void> get onGameOver => _gameOverController.stream;

  GameProvider({
    Random? random,
    void Function(int)? onPlayMerge,
    bool autoLoadState = true,
    Duration persistDebounceDuration = const Duration(seconds: 1),
  })  : _onPlayMerge = onPlayMerge,
        _persistDebounceDuration = persistDebounceDuration {
    _random = random ?? Random();
    WidgetsBinding.instance.addObserver(this);
    if (autoLoadState) {
      _loadSavedState();
    } else {
      _initFresh();
    }
  }

  /// App 启动时从 StorageService 恢复游戏快照（对应 JS loadSavedState）
  void _loadSavedState() {
    _bestScore = StorageService.loadBestScore();
    _maxCombo = StorageService.loadMaxCombo();
    final saved = StorageService.loadGameState();
    if (saved != null) {
      try {
        final boardRaw = saved['board_data'] as String?;
        if (boardRaw != null) {
          {
            final List<dynamic> rows = List<dynamic>.from(
                (boardRaw.isNotEmpty ? jsonDecode(boardRaw) : null) ?? []);
            if (rows.length == size) {
              _board = List.generate(size, (r) {
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
              _score = (saved['score'] as num?)?.toInt() ?? 0;
              _combo = (saved['combo'] as num?)?.toInt() ?? 0;
              _bestScore = (saved['bestScore'] as num?)?.toInt() ?? _bestScore;
              _maxCombo = (saved['maxCombo'] as num?)?.toInt() ?? _maxCombo;
              int maxId = 0;
              for (final row in _board) {
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
    _isOver = false;
    _score = 0;
    _combo = 0;
    _board = List.generate(size, (_) => List.filled(size, null));
    addRandomTile();
    addRandomTile();
    updateScore();
    notifyListeners();
  }

  @visibleForTesting
  void setStateForTesting({
    List<List<TileModel?>>? board,
    int? score,
    int? combo,
    bool? isOver,
  }) {
    if (board != null) _board = board;
    if (score != null) _score = score;
    if (combo != null) _combo = combo;
    if (isOver != null) _isOver = isOver;
    notifyListeners();
  }

  /// 初始化/重置游戏
  /// 溯源：映射 JS L15-26 (reset)
  void reset() {
    _isOver = false;
    _score = 0;
    _combo = 0;
    _board = List.generate(size, (_) => List.filled(size, null));
    addRandomTile();
    addRandomTile();
    updateScore();
    _schedulePersistState();
    notifyListeners();
  }

  /// 执行移动逻辑 (核心迁移逻辑)
  /// 溯源：映射 JS L32-112 (move)
  void move(Direction direction) {
    onUserMove?.call();
    _lastMoveDirection = direction;
    _lastMergedValue = 0;
    _lastMoveNoMerge = false;
    if (_isOver) {
      _emitGameOver();
      return;
    }

    bool moved = false;
    // 记录是否有任何合并发生，用于维护 combo
    List<Map<String, dynamic>> mergedTiles = [];

    // 触发滑动音效（轻量级触觉反馈）
    bool hasMerge = false;
    for (final row in _board) {
      for (final tile in row) {
        if (tile != null && tile.value > 2) {
          hasMerge = true;
          break;
        }
      }
    }
    if (_soundEnabled && hasMerge) {
      // 传入合并后的最大数值，用于分级震动
      int maxMergedValue = 0;
      for (final row in _board) {
        for (final tile in row) {
          if (tile != null && tile.value > maxMergedValue) {
            maxMergedValue = tile.value;
          }
        }
      }
      if (_onPlayMerge != null) {
        _onPlayMerge(maxMergedValue);
      } else {
        SfxService.playMoveFeedback(maxMergedValue);
      }
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
        TileModel? tile = _board[r][c];
        if (tile == null) continue;

        // 查找最远的可移动位置 (溯源：JS L54-60)
        int curR = r;
        int curC = c;
        int nextR = r + vector['y']!;
        int nextC = c + vector['x']!;

        // 循环推移 (溯源：JS L56-62)
        while (_inBounds(nextR, nextC) && _board[nextR][nextC] == null) {
          _board[nextR][nextC] = tile;
          _board[curR][curC] = null;

          curR = nextR;
          curC = nextC;
          nextR = curR + vector['y']!;
          nextC = curC + vector['x']!;
          moved = true; // 发生了位移
        }

        // 检查合并 (溯源：JS L63-82)
        if (_inBounds(nextR, nextC)) {
          TileModel? targetTile = _board[nextR][nextC];
          // 逻辑：值相等且目标位置未在本轮合并过 (JS L65)
          if (targetTile != null &&
              targetTile.value == tile.value &&
              !mergedFlags[nextR][nextC]) {
            // 合并操作：值 * 2 (溯源：JS L66)
            _board[nextR][nextC] =
                targetTile.copyWith(value: targetTile.value * 2);
            _board[curR][curC] = null;

            // 标记已合并，并更新状态
            mergedFlags[nextR][nextC] = true;
            moved = true;
            _combo++; // (溯源：JS L70)

            // 更新最大 Combo (溯源：JS L71-74)
            if (_combo > _maxCombo) {
              _maxCombo = _combo;
            }

            // 存入合并列表（在 JS 里用于触发 3D 效果，此处预留）
            mergedTiles.add(
                {'r': nextR, 'c': nextC, 'value': _board[nextR][nextC]!.value});
          }
        }
      }
    }

    if (moved) {
      // 没有任何合并时 combo 归零 (溯源：JS L87)
      if (mergedTiles.isEmpty) {
        _combo = 0;
        _lastMoveNoMerge = true; // 有效滑动但无合并
      } else {
        // 记录本次合并的最大値，供吉祥物欢呼动画使用
        _lastMergedValue = mergedTiles
            .map((e) => e['value'] as int)
            .reduce((a, b) => a > b ? a : b);
      }

      // 添加新的随机块 (溯源：JS L89)
      addRandomTile();
      // 更新全盘总分 (溯源：JS L90)
      updateScore();

      // 判断是否无路可走 (溯源：JS L91)
      if (!_movesAvailable()) {
        _markGameOver();
      }

      // 合并音效（对应 JS: if (result.mergedTiles.length > 0 && t.sound) l.playEffect('merge')）
      if (mergedTiles.isNotEmpty && _soundEnabled) {
        if (_onPlayMerge != null) {
          _onPlayMerge(_lastMergedValue);
        } else {
          SfxService.playMerge(_lastMergedValue);
        }
      }
      _schedulePersistState();
      notifyListeners();
      return;
    }

    // 即使没有发生位移，也可能已经进入无路可走状态
    if (!_movesAvailable()) {
      _markGameOver();
      _schedulePersistState();
      notifyListeners();
    }
  }

  void _markGameOver() {
    _isOver = true;
    _emitGameOver();
  }

  void _emitGameOver() {
    if (!_gameOverController.isClosed) {
      _gameOverController.add(null);
    }
  }

  /// 全盘得分计算逻辑
  /// 🚨 指令：严禁使用标准 2048 的“累加得分法”，必须严格遵循旧版的“全盘求和法”
  /// 溯源：映射 JS L113-119 (updateScore)
  void updateScore() {
    int total = 0;
    for (int r = 0; r < size; r++) {
      for (int c = 0; c < size; c++) {
        if (_board[r][c] != null) {
          total += _board[r][c]!.value;
        }
      }
    }
    _score = total;

    // 记录最佳分数 (溯源：JS L130-132)
    if (_score > _bestScore) {
      _bestScore = _score;
    }
  }

  /// 持久化当前快照到 StorageService（对应 JS saveLocalState）
  void _persistState() {
    final boardJson = List.generate(
        size,
        (r) => List.generate(size, (c) {
              final t = _board[r][c];
              if (t == null) return null;
              return <String, dynamic>{'id': t.id, 'value': t.value};
            }));
    final int novelIndex = StorageService.getCurrentNovelIndex();
    final String? currentNovelId = StorageService.getCurrentNovelId();
    StorageService.saveGameState(
      board: boardJson,
      score: _score,
      combo: _combo,
      bestScore: _bestScore,
      maxCombo: _maxCombo,
      novelIndex: novelIndex,
      currentNovelId: currentNovelId,
    );
  }

  void _schedulePersistState() {
    _persistDebounceTimer?.cancel();
    if (_persistDebounceDuration <= Duration.zero) {
      _persistState();
      return;
    }
    _persistDebounceTimer = Timer(_persistDebounceDuration, _persistState);
  }

  void flushPersistState() {
    _persistDebounceTimer?.cancel();
    _persistDebounceTimer = null;
    _persistState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      flushPersistState();
    }
  }

  /// 在空格处添加随机块 (2 或 4)
  /// 溯源：映射 JS L179-191 (addRandomTile)
  void addRandomTile() {
    List<Map<String, int>> emptyCells = [];
    for (int r = 0; r < size; r++) {
      for (int c = 0; c < size; c++) {
        if (_board[r][c] == null) {
          emptyCells.add({'r': r, 'c': c});
        }
      }
    }

    if (emptyCells.isNotEmpty) {
      final cell = emptyCells[_random.nextInt(emptyCells.length)];
      // 生成概率：2 (90%), 4 (10%) (溯源：JS L188)
      int value = _random.nextDouble() < 0.9 ? 2 : 4;
      _board[cell['r']!][cell['c']!] = TileModel(id: _nextId++, value: value);
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

  /// 彩蛋机制：通过黑客手段强行抹除指定 ID 的数据块
  void eliminateTileById(int id) {
    bool removed = false;
    for (int r = 0; r < size; r++) {
      for (int c = 0; c < size; c++) {
        if (_board[r][c]?.id == id) {
          _board[r][c] = null;
          removed = true;
          break;
        }
      }
      if (removed) break;
    }

    if (removed) {
      if (_soundEnabled) {
        if (_onPlayMerge != null) {
          _onPlayMerge(2048);
        } else {
          SfxService.playMoveFeedback(2048);
        }
      }
      if (!_isOver && _movesAvailable()) {
        _isOver = false;
      }
      _schedulePersistState();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _persistDebounceTimer?.cancel();
    _gameOverController.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
