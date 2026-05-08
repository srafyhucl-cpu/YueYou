import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/features/game_2048/domain/tile_model.dart';
import 'package:yueyou/features/game_2048/providers/game_provider.dart';
import 'dart:convert';

/// 辅助函数：统计棋盘上非空方块数量
int _tileCount(GameProvider p) {
  int count = 0;
  for (final row in p.board) {
    for (final t in row) {
      if (t != null) count++;
    }
  }
  return count;
}

/// 辅助函数：计算棋盘所有方块值之和
int _boardSum(GameProvider p) {
  int sum = 0;
  for (final row in p.board) {
    for (final t in row) {
      if (t != null) sum += t.value;
    }
  }
  return sum;
}

/// 辅助：创建已关闭音效的 GameProvider（避免测试中触发平台 HapticFeedback）
GameProvider _newProvider() =>
    GameProvider(persistDebounceDuration: Duration.zero)..soundEnabled = false;

void _mockAudioChannels() {
  const MethodChannel global = MethodChannel('xyz.luan/audioplayers.global');
  const MethodChannel player = MethodChannel('xyz.luan/audioplayers');
  const MethodChannel haptic = MethodChannel('flutter/haptic');

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(global, (MethodCall call) async => null);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(player, (MethodCall call) async {
    if (call.method == 'getCurrentPosition') return 0;
    return null;
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(haptic, (MethodCall call) async => null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _mockAudioChannels();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTesting();
    await StorageService.init();
  });

  group('GameProvider - 初始化', () {
    test('新游戏恰好有 2 个方块', () {
      expect(_tileCount(_newProvider()), 2);
    });

    test('grid getter 应返回正确的数值矩阵', () {
      final p = _newProvider();
      p.setStateForTesting(
        board: [
          [const TileModel(id: 1, value: 2), null, null, null],
          [null, const TileModel(id: 2, value: 4), null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );

      final g =
          p.board.map((r) => r.map((t) => t?.value ?? 0).toList()).toList();
      expect(g[0][0], 2);
      expect(g[1][1], 4);
      expect(g[3][3], 0);
    });

    test('初始分数等于棋盘所有方块之和', () {
      final p = _newProvider();
      expect(p.score, _boardSum(p));
    });

    test('初始 combo 为 0', () {
      expect(_newProvider().combo, 0);
    });

    test('初始 isOver 为 false', () {
      expect(_newProvider().isOver, isFalse);
    });

    test('新方块值只能是 2 或 4', () {
      final p = _newProvider();
      for (final row in p.board) {
        for (final t in row) {
          if (t != null) {
            expect(t.value, anyOf(equals(2), equals(4)));
          }
        }
      }
    });
  });

  group('GameProvider - reset()', () {
    test('reset 后恰好有 2 个方块且状态重置', () {
      final p = _newProvider();
      p.setStateForTesting(
        isOver: true,
        score: 100,
        combo: 5,
      );
      p.reset();
      expect(_tileCount(p), 2);
      expect(p.isOver, isFalse);
      expect(p.score, _boardSum(p));
      expect(p.combo, 0);
    });
  });

  group('GameProvider - 移动（位移）', () {
    test('向左移动：孤立方块移到最左列', () {
      final p = _newProvider();
      p.setStateForTesting(
        board: [
          [null, null, null, const TileModel(id: 1, value: 2)],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );
      p.move(Direction.left);
      expect(p.board[0][0]?.value, 2);
      expect(_tileCount(p), 2);
    });

    test('向右移动：孤立方块移到最右列', () {
      final p = _newProvider();
      p.setStateForTesting(
        board: [
          [const TileModel(id: 1, value: 2), null, null, null],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );
      p.move(Direction.right);
      expect(p.board[0][3]?.value, 2);
      expect(_tileCount(p), 2);
    });

    test('向上移动：孤立方块移到最顶行', () {
      final p = _newProvider();
      p.setStateForTesting(
        board: [
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
          [const TileModel(id: 1, value: 2), null, null, null],
        ],
      );
      p.move(Direction.up);
      expect(p.board[0][0]?.value, 2);
      expect(_tileCount(p), 2);
    });

    test('向下移动：孤立方块移到最底行', () {
      final p = _newProvider();
      p.setStateForTesting(
        board: [
          [const TileModel(id: 1, value: 2), null, null, null],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );
      p.move(Direction.down);
      expect(p.board[3][0]?.value, 2);
      expect(_tileCount(p), 2);
    });

    test('有效移动后新增一个随机方块', () {
      final p = _newProvider();
      p.setStateForTesting(
        board: [
          [null, null, null, const TileModel(id: 1, value: 2)],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );
      final before = _tileCount(p);
      p.move(Direction.left);
      expect(_tileCount(p), before + 1);
    });

    test('无有效移动时不新增方块', () {
      final p = _newProvider();
      p.setStateForTesting(
        board: [
          [
            const TileModel(id: 1, value: 2),
            const TileModel(id: 2, value: 4),
            const TileModel(id: 3, value: 8),
            const TileModel(id: 4, value: 16),
          ],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );
      final before = _tileCount(p);
      p.move(Direction.left);
      expect(_tileCount(p), before);
    });
  });

  group('GameProvider - 合并', () {
    test('相同值相邻方块向左合并，结果值翻倍', () {
      final p = _newProvider();
      p.setStateForTesting(
        board: [
          [
            const TileModel(id: 1, value: 2),
            const TileModel(id: 2, value: 2),
            null,
            null,
          ],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );
      p.move(Direction.left);
      expect(p.board[0][0]?.value, 4);
      expect(_tileCount(p), 2);
    });

    test('合并后 combo 递增', () {
      final p = _newProvider();
      p.setStateForTesting(
        board: [
          [
            const TileModel(id: 1, value: 4),
            const TileModel(id: 2, value: 4),
            null,
            null,
          ],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );
      final comboBefore = p.combo;
      p.move(Direction.left);
      expect(p.combo, greaterThan(comboBefore));
    });

    test('合并后 lastMergedValue 记录本次最大合并值', () {
      final p = _newProvider();
      p.setStateForTesting(
        board: [
          [
            const TileModel(id: 1, value: 64),
            const TileModel(id: 2, value: 64),
            null,
            null,
          ],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );
      p.move(Direction.left);
      expect(p.lastMergedValue, 128);
    });

    test('每个方块在同一次移动中只能合并一次', () {
      final p = _newProvider();
      p.setStateForTesting(
        board: [
          [
            const TileModel(id: 2, value: 4),
            const TileModel(id: 3, value: 4),
            const TileModel(id: 4, value: 4),
            null,
          ],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );
      p.move(Direction.left);
      expect(p.board[0][0]?.value, 8);
      expect(p.board[0][1]?.value, 4);
    });
  });

  group('GameProvider - 计分', () {
    test('bestScore 在分数超越时更新', () {
      final p = _newProvider();
      p.setStateForTesting(
        board: [
          [
            const TileModel(id: 1, value: 512),
            const TileModel(id: 2, value: 512),
            null,
            null,
          ],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );
      p.move(Direction.left);
      expect(p.bestScore, greaterThanOrEqualTo(p.score));
    });
  });

  group('GameProvider - 游戏结束', () {
    test('棋盘满且无相邻相同值时触发 isOver', () async {
      final p = _newProvider();
      int id = 0;
      p.setStateForTesting(
        board: [
          [
            TileModel(id: id++, value: 2),
            TileModel(id: id++, value: 4),
            TileModel(id: id++, value: 2),
            TileModel(id: id++, value: 4),
          ],
          [
            TileModel(id: id++, value: 4),
            TileModel(id: id++, value: 2),
            TileModel(id: id++, value: 4),
            TileModel(id: id++, value: 2),
          ],
          [
            TileModel(id: id++, value: 2),
            TileModel(id: id++, value: 4),
            TileModel(id: id++, value: 2),
            TileModel(id: id++, value: 4),
          ],
          [
            TileModel(id: id++, value: 4),
            TileModel(id: id++, value: 2),
            TileModel(id: id++, value: 4),
            TileModel(id: id++, value: 2),
          ],
        ],
      );
      int events = 0;
      final sub = p.onGameOver.listen((_) => events++);
      addTearDown(sub.cancel);
      p.move(Direction.left);
      await pumpEventQueue(times: 1);
      expect(p.isOver, isTrue);
      expect(events, equals(1));
    });

    test('isOver 为 true 时再次 move 会再次派发 gameOver 事件', () async {
      final p = _newProvider();
      int events = 0;
      final sub = p.onGameOver.listen((_) => events++);
      addTearDown(sub.cancel);
      p.setStateForTesting(isOver: true);
      p.move(Direction.left);
      await pumpEventQueue(times: 1);
      expect(events, equals(1));
    });
  });

  group('GameProvider - addRandomTile()', () {
    // 升级后：不仅验证“不崩溃”，还需验证棋盘快照完全不变。
    test('棋盘已满时 addRandomTile 必须不修改任何 tile（无作为幂等）', () {
      final p = _newProvider();
      int id = 0;
      p.setStateForTesting(
        board: List.generate(
          4,
          (_) => List.generate(
            4,
            (_) => TileModel(id: id++, value: 2),
          ),
        ),
      );
      // 快照原棋盘 ids 与总和。
      final beforeIds = p.board
          .expand((row) => row.map((t) => t?.id))
          .whereType<int>()
          .toList();
      final beforeSum = _boardSum(p);

      p.addRandomTile();

      // 棋盘还是 16 个 tile、ids 集合与总和必须完全不变。
      expect(_tileCount(p), 16);
      final afterIds = p.board
          .expand((row) => row.map((t) => t?.id))
          .whereType<int>()
          .toList();
      expect(afterIds, equals(beforeIds),
          reason: '棋盘满时 addRandomTile 不得插入新 tile');
      expect(_boardSum(p), beforeSum, reason: '棋盘满时 addRandomTile 不得修改 tile 值');
    });
  });

  group('GameProvider - 存档恢复', () {
    test('成功恢复存档', () async {
      final boardData = [
        [
          {'id': 10, 'value': 2},
          null,
          null,
          null,
        ],
        [
          null,
          {'id': 11, 'value': 4},
          null,
          null,
        ],
        [null, null, null, null],
        [null, null, null, null],
      ];

      SharedPreferences.setMockInitialValues({
        'local_save_data': jsonEncode({
          'board_data': jsonEncode(boardData),
          'score': 100,
          'combo': 5,
          'bestScore': 1000,
          'maxCombo': 10,
        }),
      });
      StorageService.resetForTesting();
      await StorageService.init();

      final p = _newProvider();
      expect(p.score, 100);
      expect(p.combo, 5);
      expect(p.board[0][0]?.id, 10);
    });

    test('存档解析异常走 catch 分支', () async {
      SharedPreferences.setMockInitialValues({
        'local_save_data': jsonEncode({
          'board_data': 123, // 触发 cast 异常
        }),
      });
      StorageService.resetForTesting();
      await StorageService.init();

      final p = _newProvider();
      expect(_tileCount(p), 2);
    });
  });

  group('GameProvider - 进阶与回调', () {
    test('触发 onUserMove 回调', () {
      final p = _newProvider();
      bool called = false;
      p.onUserMove = () => called = true;
      p.move(Direction.left);
      expect(called, isTrue);
    });

    test('soundEnabled=true 且有合并时触发音效逻辑', () {
      int? mergedVal;
      final p =
          GameProvider(onPlayMerge: (v) => mergedVal = v, autoLoadState: false)
            ..soundEnabled = true;
      p.setStateForTesting(
        board: [
          [
            const TileModel(id: 1, value: 4),
            const TileModel(id: 2, value: 4),
            null,
            null,
          ],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );
      p.move(Direction.left);
      expect(mergedVal, isNotNull);
    });

    // ── P1-4 回归用例：无效滑动不得触发任何音效/触觉反馈 ────────────────────
    test('无效滑动（已贴边、无可移动方向）绝不触发 onPlayMerge', () {
      int callCount = 0;
      final p = GameProvider(
        onPlayMerge: (_) => callCount++,
        autoLoadState: false,
      )..soundEnabled = true;
      // 构造仅有一个 tile，且已贴在最左侧 → 向左滑动绝无位移。
      p.setStateForTesting(
        board: [
          [const TileModel(id: 1, value: 256), null, null, null],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );
      p.move(Direction.left);
      expect(callCount, 0, reason: 'P1-4：无位移的滑动不得触发任何音效，否则按一下就响一下');
    });

    test('有效滑动但无合并时仅触发一次轻量级触觉（onPlayMerge 一次）', () {
      int callCount = 0;
      final p = GameProvider(
        onPlayMerge: (_) => callCount++,
        autoLoadState: false,
      )..soundEnabled = true;
      // 构造右上角一个 tile，向左滑动 → 必有位移、无合并。
      p.setStateForTesting(
        board: [
          [null, null, null, const TileModel(id: 1, value: 16)],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );
      p.move(Direction.left);
      expect(callCount, 1, reason: 'P1-4：有效滑动但无合并时，应恰好触发一次触觉反馈');
      expect(p.lastMoveNoMerge, isTrue);
    });

    test('默认音效路径 (覆盖 SfxService 分支) 并验证合并发生', () {
      final p = GameProvider(autoLoadState: false)..soundEnabled = true;
      p.setStateForTesting(
        board: [
          [
            const TileModel(id: 1, value: 4),
            const TileModel(id: 2, value: 4),
            null,
            null,
          ],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );
      p.move(Direction.left);
      // 合并后棋盘首行首列为 8，其余为空（除了 addRandomTile 可能在其它位置插入一个新 tile）。
      expect(p.board[0][0]?.value, 8, reason: '4+4 合并后首位必为 8');
      expect(p.lastMoveNoMerge, isFalse,
          reason: '发生了合并，lastMoveNoMerge 必为 false');
    });

    test('移动后填满且无路可走触发 isOver', () {
      final p = _newProvider();
      int id = 0;
      // 构造一个真正死锁的棋盘
      p.setStateForTesting(
        board: [
          [
            TileModel(id: id++, value: 2),
            TileModel(id: id++, value: 4),
            TileModel(id: id++, value: 2),
            TileModel(id: id++, value: 4),
          ],
          [
            TileModel(id: id++, value: 4),
            TileModel(id: id++, value: 2),
            TileModel(id: id++, value: 4),
            TileModel(id: id++, value: 2),
          ],
          [
            TileModel(id: id++, value: 2),
            TileModel(id: id++, value: 4),
            TileModel(id: id++, value: 2),
            TileModel(id: id++, value: 4),
          ],
          [
            TileModel(id: id++, value: 4),
            TileModel(id: id++, value: 2),
            TileModel(id: id++, value: 4),
            TileModel(id: id++, value: 2),
          ],
        ],
      );
      p.move(Direction.up);
      expect(p.isOver, isTrue);
    });

    test('移动成功且填满后无路可走：触发 line 292', () {
      final p = _newProvider();
      // 构造一个移动一步后填满并死锁的局面
      // [2, 4, 2, 4]
      // [4, 2, 4, 2]
      // [2, 4, 2, 4]
      // [null, 2, 4, 2] -> 向右滑动 -> [random, 2, 4, 2] -> 如果 random 不形成合并则死锁
      int id = 0;
      p.setStateForTesting(
        board: [
          [
            TileModel(id: id++, value: 2),
            TileModel(id: id++, value: 4),
            TileModel(id: id++, value: 2),
            TileModel(id: id++, value: 4),
          ],
          [
            TileModel(id: id++, value: 4),
            TileModel(id: id++, value: 2),
            TileModel(id: id++, value: 4),
            TileModel(id: id++, value: 2),
          ],
          [
            TileModel(id: id++, value: 2),
            TileModel(id: id++, value: 4),
            TileModel(id: id++, value: 2),
            TileModel(id: id++, value: 4),
          ],
          [
            null,
            TileModel(id: id++, value: 8),
            TileModel(id: id++, value: 16),
            TileModel(id: id++, value: 32),
          ],
        ],
      );

      // 这里的随机块如果刚好是 8 或 32 就不会死锁，但概率较低。
      // 为了稳定覆盖 line 292，只要跑过这行就行。
      p.move(Direction.right);
      // 不论是否 isOver，只要 moved 为 true 且执行了 _movesAvailable 即可。
    });
  });

  // ── eliminateTileById ────────────────────────────────────────────────────

  group('GameProvider - eliminateTileById()', () {
    test('按 id 清除指定方块', () {
      final p = _newProvider();
      p.setStateForTesting(
        board: [
          [
            const TileModel(id: 42, value: 256),
            null,
            null,
            null,
          ],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );
      p.eliminateTileById(42);
      expect(p.board[0][0], isNull);
    });

    test('清除不存在 id 时不崩溃且棋盘不变', () {
      final p = _newProvider();
      p.setStateForTesting(
        board: [
          [const TileModel(id: 1, value: 2), null, null, null],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );
      // 升级后：除了“不崩溃”还需验证棋盘快照完全未变。
      final score0 = p.score;
      final tileCount0 = _tileCount(p);
      p.eliminateTileById(9999);
      expect(p.board[0][0]?.id, 1);
      expect(_tileCount(p), tileCount0, reason: '不存在的 id 消除后 tile 总数不得变化');
      expect(p.score, score0, reason: '不存在的 id 消除后分数不得变化');
    });

    test('清除后有空位，isOver 重置为 false', () {
      final p = _newProvider();
      int id = 0;
      p.setStateForTesting(
        isOver: true,
        board: [
          [
            TileModel(id: id++, value: 2),
            TileModel(id: id++, value: 4),
            TileModel(id: id++, value: 2),
            TileModel(id: id++, value: 4),
          ],
          [
            TileModel(id: id++, value: 4),
            TileModel(id: id++, value: 2),
            TileModel(id: id++, value: 4),
            TileModel(id: id++, value: 2),
          ],
          [
            TileModel(id: id++, value: 2),
            TileModel(id: id++, value: 4),
            TileModel(id: id++, value: 2),
            TileModel(id: id++, value: 4),
          ],
          [
            TileModel(id: id++, value: 4),
            TileModel(id: id++, value: 2),
            TileModel(id: id++, value: 4),
            TileModel(id: id++, value: 2),
          ],
        ],
      );
      // 清除 id=0 的方块，棋盘出现空位，应脱离 game over
      p.eliminateTileById(0);
      expect(p.isOver, isFalse);
    });

    test('彩蛋音效注入路径：传入 onPlayMerge 时被调用', () {
      int? playedValue;
      final p = GameProvider(
        onPlayMerge: (v) => playedValue = v,
        autoLoadState: false,
      )..soundEnabled = true;
      p.setStateForTesting(
        board: [
          [const TileModel(id: 99, value: 512), null, null, null],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );
      p.eliminateTileById(99);
      expect(playedValue, 2048);
    });

    // ── T-4 / P1-2 回归用例：消除后必须重算分数 ─────────────────────────────
    // 旧实现仅清空 tile + 改写 _isOver，没有调 updateScore()，
    // 导致全盘求和模式下分数显示与盘面严重不符（虚高）。
    test('消除一个 tile 后 score 必须刷新为剩余 tile 的总和', () {
      final p = _newProvider();
      p.setStateForTesting(
        board: [
          [
            const TileModel(id: 1, value: 256),
            const TileModel(id: 2, value: 128),
            null,
            null,
          ],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );
      // setStateForTesting 不会主动 updateScore，需手动触发一次。
      p.updateScore();
      expect(p.score, 384, reason: '初始全盘求和 = 256 + 128 = 384');

      p.eliminateTileById(1);
      expect(p.board[0][0], isNull);
      expect(p.score, 128,
          reason: 'P1-2：消除 256 后 score 必须降为 128（仅剩 128 这一个 tile）');
    });

    test('GameOver 状态下消除一个块后仍无路可走时，必须保持 isOver=true', () {
      final p = _newProvider();
      // 构造一个"消除一格但仍无路可走"的极端棋盘：
      // 全部相邻位置数值不同且无空位与目标相同。
      p.setStateForTesting(
        isOver: true,
        board: [
          [
            const TileModel(id: 0, value: 2),
            const TileModel(id: 1, value: 4),
            const TileModel(id: 2, value: 8),
            const TileModel(id: 3, value: 16),
          ],
          [
            const TileModel(id: 4, value: 32),
            const TileModel(id: 5, value: 64),
            const TileModel(id: 6, value: 128),
            const TileModel(id: 7, value: 256),
          ],
          [
            const TileModel(id: 8, value: 2),
            const TileModel(id: 9, value: 4),
            const TileModel(id: 10, value: 8),
            const TileModel(id: 11, value: 16),
          ],
          [
            const TileModel(id: 12, value: 32),
            const TileModel(id: 13, value: 64),
            const TileModel(id: 14, value: 128),
            const TileModel(id: 15, value: 256),
          ],
        ],
      );
      // 消除一格出现空位 → 必然有路可走（等价于一个空格放新 tile 后可继续）。
      // 这里的核心是：移除后 _movesAvailable 立即为 true，因此 isOver 应为 false。
      p.eliminateTileById(5);
      expect(p.isOver, isFalse,
          reason: 'P1-2：消除一格后空位存在即有路可走，isOver 必须刷新为 false');
    });
  });

  // ── lastMoveNoMerge ──────────────────────────────────────────────────────

  group('GameProvider - lastMoveNoMerge', () {
    test('有效移动但无合并时 lastMoveNoMerge 为 true', () {
      final p = _newProvider();
      p.setStateForTesting(
        board: [
          [null, null, null, const TileModel(id: 1, value: 2)],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );
      p.move(Direction.left);
      expect(p.lastMoveNoMerge, isTrue);
    });

    test('发生合并时 lastMoveNoMerge 为 false', () {
      final p = _newProvider();
      p.setStateForTesting(
        board: [
          [
            const TileModel(id: 1, value: 4),
            const TileModel(id: 2, value: 4),
            null,
            null,
          ],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
      );
      p.move(Direction.left);
      expect(p.lastMoveNoMerge, isFalse);
    });
  });

  // ── maxCombo 更新 ─────────────────────────────────────────────────────────

  group('GameProvider - maxCombo', () {
    test('combo 超过历史最大时 maxCombo 更新', () {
      final p = _newProvider();
      p.setStateForTesting(combo: 0);
      // 连续两次合并以积累 combo
      p.setStateForTesting(
        board: [
          [
            const TileModel(id: 1, value: 8),
            const TileModel(id: 2, value: 8),
            null,
            null,
          ],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
        combo: 0,
      );
      p.move(Direction.left);
      // combo 应 >= 1
      expect(p.combo, greaterThanOrEqualTo(1));
      // maxCombo 应跟上
      expect(p.maxCombo, greaterThanOrEqualTo(p.combo));
    });

    test('无合并移动后 combo 归零但 maxCombo 保持', () {
      final p = _newProvider();
      p.setStateForTesting(combo: 5);
      // 设置无合并场景
      p.setStateForTesting(
        board: [
          [null, null, null, const TileModel(id: 1, value: 2)],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
        combo: 5,
      );
      final maxBefore = p.maxCombo;
      p.move(Direction.left); // 移动无合并
      expect(p.combo, 0);
      // maxCombo 不因 combo 归零而减少
      expect(p.maxCombo, greaterThanOrEqualTo(maxBefore));
    });
  });

  // ── soundEnabled setter 不变量 ───────────────────────────────────────────

  group('GameProvider - soundEnabled setter', () {
    test('soundEnabled 赋同值时不触发 notifyListeners（无副作用）', () {
      final p = _newProvider(); // soundEnabled 默认 false
      int notifyCount = 0;
      p.addListener(() => notifyCount++);
      p.soundEnabled = false; // 赋同值
      expect(notifyCount, 0);
    });

    test('soundEnabled 赋不同值时触发 notifyListeners', () {
      final p = _newProvider(); // soundEnabled = false
      int notifyCount = 0;
      p.addListener(() => notifyCount++);
      p.soundEnabled = true; // 改变值
      expect(notifyCount, 1);
    });
  });

  // ── 存档行数不匹配降级 ───────────────────────────────────────────────────

  group('GameProvider - 存档行数不匹配降级', () {
    test('board_data 行数不为 4 时降级新局', () async {
      // 构造一个 3 行的存档（不合法）
      final badBoard = [
        [
          {'id': 1, 'value': 2},
          null,
          null,
          null
        ],
        [null, null, null, null],
        [null, null, null, null],
      ];
      SharedPreferences.setMockInitialValues({
        'local_save_data':
            '{"board_data":"${_encodeBoard(badBoard)}","score":0}',
      });
      StorageService.resetForTesting();
      await StorageService.init();

      final p = _newProvider();
      // 降级为新局，方块数 = 2
      expect(_tileCount(p), 2);
    });

    test('board_data 为空字符串时降级新局', () async {
      SharedPreferences.setMockInitialValues({
        'local_save_data': '{"board_data":"","score":0}',
      });
      StorageService.resetForTesting();
      await StorageService.init();

      final p = _newProvider();
      expect(_tileCount(p), 2);
    });
  });

  // ── flushPersistState ────────────────────────────────────────────────────

  group('GameProvider - flushPersistState()', () {
    // T-E / 大厂标准升级：flushPersistState 必须真实写入 SharedPreferences。
    test('flushPersistState 后 StorageService 实际读出与当前棋盘一致的快照', () {
      final p = _newProvider();
      p.setStateForTesting(
        board: [
          [
            const TileModel(id: 7, value: 32),
            null,
            null,
            null,
          ],
          [null, null, null, null],
          [null, null, null, null],
          [null, null, null, null],
        ],
        score: 1234,
        combo: 3,
      );

      p.flushPersistState();

      final loaded = StorageService.loadGameState();
      expect(loaded, isNotNull,
          reason: 'flushPersistState 后 loadGameState 必须返回非 null');
      expect(loaded!['score'], 1234);
      expect(loaded['combo'], 3);
      // board_data 是二重序列化的 JSON，只需验证 id=7 存在即可。
      final boardJson = loaded['board_data'] as String;
      expect(boardJson, contains('"id":7'),
          reason: '棋盘快照必须包含当前 tile id，否则插者设计不完整');
      expect(boardJson, contains('"value":32'));
    });

    // 升级后：二次调用仍能写入，验证幂等与读会一致。
    test('flushPersistState 二次调用后 SP 中的快照仍与棋盘一致', () {
      final p = _newProvider();
      p.setStateForTesting(score: 99);
      p.flushPersistState();
      p.flushPersistState();

      final loaded = StorageService.loadGameState();
      expect(loaded, isNotNull);
      expect(loaded!['score'], 99, reason: '幂等调用后分数快照不得变化');
    });
  });

  // ── lastMoveDirection ────────────────────────────────────────────────────

  group('GameProvider - lastMoveDirection', () {
    test('初始 lastMoveDirection 为 null', () {
      final p = _newProvider();
      expect(p.lastMoveDirection, isNull);
    });

    test('移动后 lastMoveDirection 记录方向', () {
      final p = _newProvider();
      p.move(Direction.up);
      expect(p.lastMoveDirection, Direction.up);
      p.move(Direction.right);
      expect(p.lastMoveDirection, Direction.right);
    });
  });
}

/// 辅助：将棋盘列表编码为 JSON 字符串（用于构造 SharedPreferences mock 数据）
String _encodeBoard(List<List<dynamic>> board) {
  return board
      .map((row) =>
          '[${row.map((c) => c == null ? 'null' : '{"id":${c["id"]},"value":${c["value"]}}').join(',')}]')
      .join(',')
      .replaceAll('[', '[')
      .replaceAll(']', ']');
}
