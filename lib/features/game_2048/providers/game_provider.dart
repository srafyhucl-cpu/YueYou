import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';
import 'package:yueyou/features/audio/providers/tts_engine_provider.dart';
import 'package:yueyou/features/audio/services/sfx_service.dart';
import 'package:yueyou/features/game_2048/domain/game_engine.dart';
import 'package:yueyou/features/game_2048/domain/tile_model.dart';
import 'package:yueyou/features/settings/providers/settings_provider.dart';

export 'package:yueyou/features/game_2048/domain/game_engine.dart'
    show Direction, GameEngine, GameState;

final gameProvider = ChangeNotifierProvider<GameProvider>((ref) {
  final provider = GameProvider();
  provider.soundEnabled = ref.read(settingsProvider).sound;
  ref.listen(settingsProvider, (_, next) {
    provider.soundEnabled = next.sound;
  });
  provider.onUserMove = () => ref.read(ttsEngineProvider).notifyUserActivity();
  return provider;
});

/// 2048 的 Flutter 编排层。
///
/// 矩阵移动、合并、计分和结束判断全部委托给纯 Dart [GameEngine]；
/// 本类只处理随机数、存档、音效、生命周期、通知和 TTS 用户活动。
class GameProvider extends ChangeNotifier with WidgetsBindingObserver {
  final GameEngine _engine = const GameEngine();
  final Random _random;
  final void Function(int)? _onPlayMerge;
  final Duration _persistDebounceDuration;
  final StreamController<void> _gameOverController =
      StreamController<void>.broadcast();

  late GameState _state;
  Timer? _persistDebounceTimer;
  int _nextId = DateTime.now().millisecondsSinceEpoch;
  bool _soundEnabled = true;
  Direction? _lastMoveDirection;
  int _lastMergedValue = 0;
  bool _lastMoveNoMerge = false;

  /// 棋盘边长。
  int get size => GameEngine.size;

  List<List<TileModel?>> get board => _state.board;
  int get score => _state.score;
  int get bestScore => _state.bestScore;
  int get combo => _state.combo;
  int get maxCombo => _state.maxCombo;
  bool get isOver => _state.isOver;

  bool get soundEnabled => _soundEnabled;
  set soundEnabled(bool value) {
    if (_soundEnabled == value) return;
    _soundEnabled = value;
    notifyListeners();
  }

  Direction? get lastMoveDirection => _lastMoveDirection;
  int get lastMergedValue => _lastMergedValue;
  bool get lastMoveNoMerge => _lastMoveNoMerge;

  /// 用户有效操作回调，由应用组合根注入以重置 TTS 空闲计时器。
  void Function()? onUserMove;

  Stream<void> get onGameOver => _gameOverController.stream;

  GameProvider({
    Random? random,
    void Function(int)? onPlayMerge,
    bool autoLoadState = true,
    Duration persistDebounceDuration = const Duration(seconds: 1),
  })  : _random = random ?? Random(),
        _onPlayMerge = onPlayMerge,
        _persistDebounceDuration = persistDebounceDuration {
    WidgetsBinding.instance.addObserver(this);
    if (autoLoadState) {
      _loadSavedState();
    } else {
      _initFresh();
    }
  }

  /// 从本地存档恢复领域状态，解析失败时回退到新局。
  void _loadSavedState() {
    final bestScore = StorageService.loadBestScore();
    final maxCombo = StorageService.loadMaxCombo();
    final saved = StorageService.loadGameState();
    if (saved != null) {
      try {
        final rawBoard = saved['board_data'];
        final boardJson = rawBoard is String && rawBoard.isNotEmpty
            ? jsonDecode(rawBoard)
            : null;
        if (boardJson is List && boardJson.length == size) {
          final board = List<List<TileModel?>>.generate(size, (row) {
            final cells = boardJson[row];
            if (cells is! List || cells.length != size) {
              throw const FormatException('棋盘行结构无效');
            }
            return List<TileModel?>.generate(size, (column) {
              final cell = cells[column];
              if (cell == null) return null;
              if (cell is! Map) throw const FormatException('方块结构无效');
              final json = cell.cast<String, dynamic>();
              return TileModel(
                id: (json['id'] as num).toInt(),
                value: (json['value'] as num).toInt(),
              );
            });
          });
          final maxId = board
              .expand((row) => row)
              .whereType<TileModel>()
              .fold<int>(0, (max, tile) => tile.id > max ? tile.id : max);
          _nextId = maxId + 1;
          _state = GameState(
            board: board,
            score: (saved['score'] as num?)?.toInt() ?? 0,
            bestScore: (saved['bestScore'] as num?)?.toInt() ?? bestScore,
            combo: (saved['combo'] as num?)?.toInt() ?? 0,
            maxCombo: (saved['maxCombo'] as num?)?.toInt() ?? maxCombo,
            isOver: !_engine.movesAvailable(GameState(board: board)),
          );
          notifyListeners();
          return;
        }
      } catch (e, stack) {
        CyberLogger.captureWarning(
          e,
          stack: stack,
          tag: 'game',
          extra: {'context': '游戏快照恢复失败，新开一局'},
        );
      }
    }
    _initFresh();
  }

  void _initFresh() {
    _state = GameState(board: _emptyBoard());
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
    _state = _state.copyWith(
      board: board,
      score: score,
      combo: combo,
      isOver: isOver,
    );
    notifyListeners();
  }

  /// 初始化或重置游戏。
  void reset() {
    _state = GameState(board: _emptyBoard());
    addRandomTile();
    addRandomTile();
    updateScore();
    _schedulePersistState();
    notifyListeners();
  }

  /// 执行一次移动，并在成功移动后由编排层选择随机出生块。
  void move(Direction direction) {
    onUserMove?.call();
    _lastMoveDirection = direction;
    _lastMergedValue = 0;
    _lastMoveNoMerge = false;

    final result = _engine.move(_state, direction);
    _state = result.state;
    if (!result.moved) {
      if (_state.isOver) _emitGameOver();
      if (_state.isOver) notifyListeners();
      return;
    }

    _lastMergedValue = result.lastMergedValue;
    _lastMoveNoMerge = result.lastMoveNoMerge;
    addRandomTile();
    if (_state.isOver) _emitGameOver();
    _playMoveFeedback();
    _schedulePersistState();
    notifyListeners();
  }

  void _playMoveFeedback() {
    if (!_soundEnabled) return;
    if (_lastMergedValue > 0) {
      _onPlayMerge?.call(_lastMergedValue);
      if (_onPlayMerge == null) SfxService.playMerge(_lastMergedValue);
      return;
    }

    var maxBoardValue = 0;
    for (final row in board) {
      for (final tile in row) {
        if (tile != null && tile.value > maxBoardValue) {
          maxBoardValue = tile.value;
        }
      }
    }
    _onPlayMerge?.call(maxBoardValue);
    if (_onPlayMerge == null) SfxService.playMoveFeedback(maxBoardValue);
  }

  /// 按当前盘面重新计算全盘求和分数。
  void updateScore() {
    final score = _engine.scoreOf(_state);
    _state = _state.copyWith(
      score: score,
      bestScore: score > _state.bestScore ? score : _state.bestScore,
    );
  }

  /// 在空位随机添加 2 或 4；随机性只存在于编排层。
  void addRandomTile() {
    final cells = _engine.emptyCells(_state);
    if (cells.isEmpty) return;
    final cell = cells[_random.nextInt(cells.length)];
    final value = _random.nextDouble() < 0.9 ? 2 : 4;
    _state = _engine.addTile(
      _state,
      cell.row,
      cell.column,
      TileModel(id: _nextId++, value: value),
    );
  }

  /// 复制当前游戏快照到本地存储。
  void _persistState() {
    final boardJson = board.map((row) {
      return row.map((tile) {
        if (tile == null) return null;
        return <String, dynamic>{'id': tile.id, 'value': tile.value};
      }).toList();
    }).toList();
    StorageService.saveGameState(
      board: boardJson,
      score: score,
      combo: combo,
      bestScore: bestScore,
      maxCombo: maxCombo,
      novelIndex: StorageService.getCurrentNovelIndex(),
      currentNovelId: StorageService.getCurrentNovelId(),
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
    if (state == AppLifecycleState.paused) flushPersistState();
  }

  /// 彩蛋：移除指定方块并重新计算结束状态。
  void eliminateTileById(int id) {
    final exists = board.expand((row) => row).any((tile) => tile?.id == id);
    if (!exists) return;
    _state = _engine.removeTile(_state, id);
    updateScore();
    if (_soundEnabled) {
      _onPlayMerge?.call(2048);
      if (_onPlayMerge == null) SfxService.playMoveFeedback(2048);
    }
    _schedulePersistState();
    notifyListeners();
  }

  void _emitGameOver() {
    if (!_gameOverController.isClosed) _gameOverController.add(null);
  }

  static List<List<TileModel?>> _emptyBoard() {
    return List.generate(
      GameEngine.size,
      (_) => List<TileModel?>.filled(GameEngine.size, null),
    );
  }

  @override
  void dispose() {
    _persistDebounceTimer?.cancel();
    _gameOverController.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
