import 'package:test/test.dart';
import 'package:yueyou/features/game_2048/domain/game_engine.dart';
import 'package:yueyou/features/game_2048/domain/tile_model.dart';

List<List<TileModel?>> _board(List<List<int?>> values) {
  var id = 1;
  return values
      .map((row) => row
          .map((value) =>
              value == null ? null : TileModel(id: id++, value: value))
          .toList())
      .toList();
}

List<int?> _values(GameState state) {
  return state.board.expand((row) => row.map((tile) => tile?.value)).toList();
}

void main() {
  const engine = GameEngine();

  test('纯 Dart 引擎不依赖 Flutter Binding', () {
    final state = GameState(
        board: _board([
      [2, null, null, null],
      [null, null, null, null],
      [null, null, null, null],
      [null, null, null, null],
    ]));

    final result = engine.move(state, Direction.right);

    expect(result.moved, isTrue);
    expect(result.state.board[0][3]?.value, 2);
  });

  test('同向移动时相邻相同方块各只合并一次', () {
    final state = GameState(
        board: _board([
      [2, 2, 2, 2],
      [null, null, null, null],
      [null, null, null, null],
      [null, null, null, null],
    ]));

    final result = engine.move(state, Direction.left);

    expect(result.lastMergedValue, 4);
    expect(_values(result.state).take(4), [4, 4, null, null]);
  });

  test('连续合并保持输入状态不变并维护 combo', () {
    final state = GameState(
      board: _board([
        [2, 2, 4, 4],
        [null, null, null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]),
      combo: 2,
      maxCombo: 3,
    );

    final result = engine.move(state, Direction.left);

    expect(state.board[0][0]?.value, 2);
    expect(result.state.board[0][0]?.value, 4);
    expect(result.state.board[0][1]?.value, 8);
    expect(result.state.combo, 4);
    expect(result.state.maxCombo, 4);
    expect(result.lastMoveNoMerge, isFalse);
  });

  test('有效但无合并的移动会重置 combo 并标记 noMerge', () {
    final state = GameState(
      board: _board([
        [2, null, null, null],
        [null, null, null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]),
      combo: 4,
    );

    final result = engine.move(state, Direction.right);

    expect(result.moved, isTrue);
    expect(result.lastMoveNoMerge, isTrue);
    expect(result.state.combo, 0);
  });

  test('满盘无合并时判定游戏结束，存在空位时不结束', () {
    final blocked = GameState(
        board: _board([
      [2, 4, 8, 16],
      [16, 8, 4, 2],
      [2, 4, 8, 16],
      [16, 8, 4, 2],
    ]));
    final open = GameState(
        board: _board([
      [2, 4, 8, null],
      [16, 8, 4, 2],
      [2, 4, 8, 16],
      [16, 8, 4, 2],
    ]));

    expect(engine.move(blocked, Direction.left).state.isOver, isTrue);
    expect(engine.move(open, Direction.left).state.isOver, isFalse);
  });

  test('添加和移除方块由纯函数返回新状态并重新计分', () {
    final state = GameState(
        board: _board([
      [2, null, null, null],
      [null, null, null, null],
      [null, null, null, null],
      [null, null, null, null],
    ]));

    final added =
        engine.addTile(state, 0, 1, const TileModel(id: 99, value: 4));
    final removed = engine.removeTile(added, 99);

    expect(state.board[0][1], isNull);
    expect(added.score, 6);
    expect(removed.score, 2);
    expect(removed.board[0][1], isNull);
  });
}
