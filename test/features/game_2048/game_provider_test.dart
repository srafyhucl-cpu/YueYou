import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yueyou/core/database/storage_service.dart';
import 'package:yueyou/features/game_2048/domain/tile_model.dart';
import 'package:yueyou/features/game_2048/providers/game_provider.dart';

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
GameProvider _newProvider() => GameProvider()..soundEnabled = false;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTesting();
    await StorageService.init();
  });

  // ── 初始化状态 ───────────────────────────────────────────────────────────────

  group('GameProvider - 初始化', () {
    test('新游戏恰好有 2 个方块', () {
      expect(_tileCount(_newProvider()), 2);
    });

    test('初始分数等于棋盘所有方块之和（全盘求和法）', () {
      final p = _newProvider();
      expect(p.score, _boardSum(p));
    });

    test('初始 combo 为 0', () {
      expect(_newProvider().combo, 0);
    });

    test('初始 isOver 为 false', () {
      expect(_newProvider().isOver, isFalse);
    });

    test('初始 showGameOverDialog 为 false', () {
      expect(_newProvider().showGameOverDialog, isFalse);
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

  // ── 重置 ─────────────────────────────────────────────────────────────────────

  group('GameProvider - reset()', () {
    test('reset 后恰好有 2 个方块', () {
      final p = _newProvider()..reset();
      expect(_tileCount(p), 2);
    });

    test('reset 后 isOver 为 false', () {
      final p = _newProvider()..reset();
      expect(p.isOver, isFalse);
    });

    test('reset 后 combo 归零', () {
      final p = _newProvider();
      p.combo = 9; // 人为设置
      p.reset();
      expect(p.combo, 0);
    });

    test('reset 后分数等于棋盘求和', () {
      final p = _newProvider()..reset();
      expect(p.score, _boardSum(p));
    });
  });

  // ── 移动：位移 ───────────────────────────────────────────────────────────────

  group('GameProvider - 移动（位移）', () {
    test('向左移动：孤立方块移到最左列', () {
      final p = _newProvider();
      p.board = List.generate(4, (_) => List.filled(4, null));
      p.board[0][3] = const TileModel(id: 1, value: 2);
      p.move(Direction.left);

      // 方块必须到达第 0 列，且值保持 2；addRandomTile 后总共 2 块
      expect(p.board[0][0]?.value, 2);
      expect(_tileCount(p), 2);
    });

    test('向右移动：孤立方块移到最右列', () {
      final p = _newProvider();
      p.board = List.generate(4, (_) => List.filled(4, null));
      p.board[0][0] = const TileModel(id: 1, value: 2);
      p.move(Direction.right);

      expect(p.board[0][3]?.value, 2);
      expect(_tileCount(p), 2);
    });

    test('向上移动：孤立方块移到最顶行', () {
      final p = _newProvider();
      p.board = List.generate(4, (_) => List.filled(4, null));
      p.board[3][0] = const TileModel(id: 1, value: 2);
      p.move(Direction.up);

      expect(p.board[0][0]?.value, 2);
      expect(_tileCount(p), 2);
    });

    test('向下移动：孤立方块移到最底行', () {
      final p = _newProvider();
      p.board = List.generate(4, (_) => List.filled(4, null));
      p.board[0][0] = const TileModel(id: 1, value: 2);
      p.move(Direction.down);

      expect(p.board[3][0]?.value, 2);
      expect(_tileCount(p), 2);
    });

    test('有效移动后新增一个随机方块', () {
      final p = _newProvider();
      p.board = List.generate(4, (_) => List.filled(4, null));
      p.board[0][3] = const TileModel(id: 1, value: 2); // 向左有移动空间
      final before = _tileCount(p);
      p.move(Direction.left);
      expect(_tileCount(p), before + 1);
    });

    test('无有效移动时不新增方块', () {
      final p = _newProvider();
      // 满行且全为不同值，向左均无法移动
      p.board = List.generate(4, (_) => List.filled(4, null));
      p.board[0][0] = const TileModel(id: 1, value: 2);
      p.board[0][1] = const TileModel(id: 2, value: 4);
      p.board[0][2] = const TileModel(id: 3, value: 8);
      p.board[0][3] = const TileModel(id: 4, value: 16);
      final before = _tileCount(p);
      p.move(Direction.left); // 已贴左，无合并，不会移动
      expect(_tileCount(p), before);
    });
  });

  // ── 移动：合并 ───────────────────────────────────────────────────────────────

  group('GameProvider - 合并', () {
    test('相同值相邻方块向左合并，结果值翻倍', () {
      final p = _newProvider();
      p.board = List.generate(4, (_) => List.filled(4, null));
      p.board[0][0] = const TileModel(id: 1, value: 2);
      p.board[0][1] = const TileModel(id: 2, value: 2);
      p.move(Direction.left);

      expect(p.board[0][0]?.value, 4);
      expect(p.board[0][1], isNull);
    });

    test('合并后 combo 递增', () {
      final p = _newProvider();
      p.board = List.generate(4, (_) => List.filled(4, null));
      p.board[0][0] = const TileModel(id: 1, value: 4);
      p.board[0][1] = const TileModel(id: 2, value: 4);
      final comboBefore = p.combo;
      p.move(Direction.left);
      expect(p.combo, greaterThan(comboBefore));
    });

    test('有效移动但无合并时 combo 归零', () {
      final p = _newProvider();
      p.board = List.generate(4, (_) => List.filled(4, null));
      p.board[0][0] = const TileModel(id: 1, value: 2);
      p.board[0][2] = const TileModel(id: 2, value: 4); // 不同值，不合并
      p.combo = 5; // 人为设置
      p.move(Direction.left);
      expect(p.combo, 0);
    });

    test('合并后 lastMergedValue 记录本次最大合并值', () {
      final p = _newProvider();
      p.board = List.generate(4, (_) => List.filled(4, null));
      p.board[0][0] = const TileModel(id: 1, value: 64);
      p.board[0][1] = const TileModel(id: 2, value: 64); // 合并后 = 128
      p.move(Direction.left);
      expect(p.lastMergedValue, 128);
    });

    test('每个方块在同一次移动中只能合并一次（4+4+4+4 → 8+8，而非 16）', () {
      final p = _newProvider();
      p.board = List.generate(4, (_) => List.filled(4, null));
      p.board[0][0] = const TileModel(id: 1, value: 4);
      p.board[0][1] = const TileModel(id: 2, value: 4);
      p.board[0][2] = const TileModel(id: 3, value: 4);
      p.board[0][3] = const TileModel(id: 4, value: 4);
      p.move(Direction.left);

      // 期望：[8, 8, null, null+新随机块]
      expect(p.board[0][0]?.value, 8);
      expect(p.board[0][1]?.value, 8);
    });

    test('不同值相邻方块不合并', () {
      final p = _newProvider();
      p.board = List.generate(4, (_) => List.filled(4, null));
      p.board[0][0] = const TileModel(id: 1, value: 2);
      p.board[0][1] = const TileModel(id: 2, value: 4);
      p.move(Direction.left);

      // 2 和 4 不合并，均保留原值
      expect(p.board[0][0]?.value, 2);
      expect(p.board[0][1]?.value, 4);
    });
  });

  // ── 计分规则（全盘求和法）────────────────────────────────────────────────────

  group('GameProvider - 计分', () {
    test('move 后分数等于棋盘所有方块之和', () {
      final p = _newProvider();
      p.board = List.generate(4, (_) => List.filled(4, null));
      p.board[0][0] = const TileModel(id: 1, value: 2);
      p.board[0][2] = const TileModel(id: 2, value: 4);
      p.move(Direction.left);
      expect(p.score, _boardSum(p));
    });

    test('合并后分数依然等于棋盘求和（而非累加合并值）', () {
      final p = _newProvider();
      p.board = List.generate(4, (_) => List.filled(4, null));
      p.board[0][0] = const TileModel(id: 1, value: 8);
      p.board[0][1] = const TileModel(id: 2, value: 8); // 合并后 = 16
      p.move(Direction.left);
      // 全盘求和：16（合并块）+ 新随机 2 或 4
      expect(p.score, _boardSum(p));
    });

    test('bestScore 在分数超越时更新', () {
      final p = _newProvider();
      p.board = List.generate(4, (_) => List.filled(4, null));
      p.board[0][0] = const TileModel(id: 1, value: 512);
      p.board[0][1] = const TileModel(id: 2, value: 512); // 合并后 1024
      p.move(Direction.left);
      expect(p.bestScore, greaterThanOrEqualTo(p.score));
    });
  });

  // ── 游戏结束判断 ──────────────────────────────────────────────────────────────

  group('GameProvider - 游戏结束', () {
    test('棋盘满且无相邻相同值时触发 isOver', () {
      final p = _newProvider();
      // 构造棋盘：[2,4,2,4 / 4,2,4,2 / ...] — 无任何相邻等值
      int id = 0;
      p.board = List.generate(
        4,
        (r) => List.generate(4, (c) {
          final v = (r + c) % 2 == 0 ? 2 : 4;
          return TileModel(id: id++, value: v);
        }),
      );

      p.move(Direction.left); // 无法移动 → 触发游戏结束检测

      expect(p.isOver, isTrue);
      expect(p.showGameOverDialog, isTrue);
    });

    test('dismissGameOver 关闭弹窗但 isOver 保持 true', () {
      final p = _newProvider();
      int id = 0;
      p.board = List.generate(
        4,
        (r) => List.generate(4, (c) {
          final v = (r + c) % 2 == 0 ? 2 : 4;
          return TileModel(id: id++, value: v);
        }),
      );
      p.move(Direction.left);
      expect(p.isOver, isTrue);

      p.dismissGameOver();
      expect(p.isOver, isTrue); // 仍然结束
      expect(p.showGameOverDialog, isFalse); // 弹窗已关
    });

    test('isOver 为 true 时再次 move 弹出 showGameOverDialog', () {
      final p = _newProvider();
      int id = 0;
      p.board = List.generate(
        4,
        (r) => List.generate(4, (c) {
          final v = (r + c) % 2 == 0 ? 2 : 4;
          return TileModel(id: id++, value: v);
        }),
      );
      p.move(Direction.left); // 触发 isOver
      p.dismissGameOver(); // 关闭弹窗

      p.move(Direction.right); // 再次移动 → 弹窗重新弹出
      expect(p.showGameOverDialog, isTrue);
    });

    test('reset 后 isOver 为 false 可正常游戏', () {
      final p = _newProvider();
      int id = 0;
      p.board = List.generate(
        4,
        (r) => List.generate(4, (c) {
          final v = (r + c) % 2 == 0 ? 2 : 4;
          return TileModel(id: id++, value: v);
        }),
      );
      p.move(Direction.left);
      expect(p.isOver, isTrue);

      p.reset();
      expect(p.isOver, isFalse);
      expect(_tileCount(p), 2);
    });
  });

  // ── addRandomTile ────────────────────────────────────────────────────────────

  group('GameProvider - addRandomTile()', () {
    test('空棋盘上调用后有 1 个方块', () {
      final p = _newProvider();
      p.board = List.generate(4, (_) => List.filled(4, null));
      p.addRandomTile();
      expect(_tileCount(p), 1);
    });

    test('新方块值为 2 或 4', () {
      final p = _newProvider();
      p.board = List.generate(4, (_) => List.filled(4, null));
      p.addRandomTile();
      TileModel? added;
      for (final row in p.board) {
        for (final t in row) {
          if (t != null) added = t;
        }
      }
      expect(added, isNotNull);
      expect(added!.value, anyOf(equals(2), equals(4)));
    });

    test('棋盘已满时调用不崩溃且方块数不变', () {
      final p = _newProvider();
      int id = 0;
      p.board = List.generate(
        4,
        (_) => List.generate(4, (_) => TileModel(id: id++, value: 2)),
      );
      expect(() => p.addRandomTile(), returnsNormally);
      expect(_tileCount(p), 16);
    });
  });
}
