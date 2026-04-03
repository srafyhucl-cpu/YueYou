import 'dart:io';

void main() {
  final files = [
    'test/features/game_2048/game_provider_test.dart',
    'test/features/game_2048/square_board_test.dart',
  ];

  for (final file in files) {
    var content = File(file).readAsStringSync();

    // 1. 处理 p.board[x][y] = const TileModel(...)
    // 这个由于可能连续多行，我们先把 p.board[r][c] = value 收集起来。
    // 但是这里更简单的方式是，直接将这些赋值替换成对 board 数组的部分修改然后再 setStateForTesting。
    // 为了不搞复杂 AST 解析，我们可以使用简单的正则，将形如:
    // p.board = List.generate(4, (_) => List.filled(4, null));
    // p.board[0][0] = const TileModel(id: 1, value: 2);
    // 的模式替换掉。

    // 实际上由于测试文件就这两个，我们可以直接替换具体的行

    content = content.replaceAll(
        'p.isOver = true;\n      p.score = 100;\n      p.combo = 5;',
        'p.setStateForTesting(isOver: true, score: 100, combo: 5);');

    content = content.replaceAll(
        'p.board = List.generate(4, (_) => List.filled(4, null));\n      p.board[0][3] = const TileModel(id: 1, value: 2);',
        '''p.setStateForTesting(board: [
        [null, null, null, const TileModel(id: 1, value: 2)],
        [null, null, null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]);''');

    content = content.replaceAll(
        'p.board = List.generate(4, (_) => List.filled(4, null));\n      p.board[0][0] = const TileModel(id: 1, value: 2);',
        '''p.setStateForTesting(board: [
        [const TileModel(id: 1, value: 2), null, null, null],
        [null, null, null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]);''');

    content = content.replaceAll(
        'p.board = List.generate(4, (_) => List.filled(4, null));\n      p.board[0][2] = const TileModel(id: 1, value: 2);',
        '''p.setStateForTesting(board: [
        [null, null, const TileModel(id: 1, value: 2), null],
        [null, null, null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]);''');

    content = content.replaceAll(
        'p.board = List.generate(4, (_) => List.filled(4, null));\n      p.board[3][1] = const TileModel(id: 1, value: 2);',
        '''p.setStateForTesting(board: [
        [null, null, null, null],
        [null, null, null, null],
        [null, null, null, null],
        [null, const TileModel(id: 1, value: 2), null, null],
      ]);''');

    content = content.replaceAll(
        'p.board = List.generate(4, (_) => List.filled(4, null));\n      p.board[0][0] = const TileModel(id: 1, value: 4);\n      p.board[0][2] = const TileModel(id: 2, value: 2);',
        '''p.setStateForTesting(board: [
        [const TileModel(id: 1, value: 4), null, const TileModel(id: 2, value: 2), null],
        [null, null, null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]);''');

    content = content.replaceAll(
        'p.board = List.generate(4, (_) => List.filled(4, null));\n      p.board[0][0] = const TileModel(id: 1, value: 2);\n      p.board[0][1] = const TileModel(id: 2, value: 4);',
        '''p.setStateForTesting(board: [
        [const TileModel(id: 1, value: 2), const TileModel(id: 2, value: 4), null, null],
        [null, null, null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]);''');

    content = content.replaceAll(
        'p.board = List.generate(4, (_) => List.filled(4, null));\n      p.board[0][0] = const TileModel(id: 1, value: 2);\n      p.board[0][1] = const TileModel(id: 2, value: 2);',
        '''p.setStateForTesting(board: [
        [const TileModel(id: 1, value: 2), const TileModel(id: 2, value: 2), null, null],
        [null, null, null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]);''');

    content = content.replaceAll(
        'p.board = List.generate(4, (_) => List.filled(4, null));\n      p.board[0][0] = const TileModel(id: 1, value: 4);\n      p.board[0][1] = const TileModel(id: 2, value: 4);',
        '''p.setStateForTesting(board: [
        [const TileModel(id: 1, value: 4), const TileModel(id: 2, value: 4), null, null],
        [null, null, null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]);''');

    content = content.replaceAll(
        'p.board = List.generate(4, (_) => List.filled(4, null));\n      p.board[0][0] = const TileModel(id: 1, value: 64);\n      p.board[0][1] = const TileModel(id: 2, value: 64);',
        '''p.setStateForTesting(board: [
        [const TileModel(id: 1, value: 64), const TileModel(id: 2, value: 64), null, null],
        [null, null, null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]);''');

    content = content.replaceAll(
        'p.board = List.generate(4, (_) => List.filled(4, null));\n      p.board[0][0] = const TileModel(id: 1, value: 4);\n      p.board[0][1] = const TileModel(id: 2, value: 4);\n      p.board[0][2] = const TileModel(id: 3, value: 4);',
        '''p.setStateForTesting(board: [
        [const TileModel(id: 1, value: 4), const TileModel(id: 2, value: 4), const TileModel(id: 3, value: 4), null],
        [null, null, null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]);''');

    content = content.replaceAll('p.isOver = false;\n      p.board =',
        'p.setStateForTesting(isOver: false, board:');

    content = content.replaceAll(
        'p.isOver = true;', 'p.setStateForTesting(isOver: true);');

    content = content.replaceAll(
        'p.board[0][1] = const TileModel(id: 1, value: 512);\n      p.board[0][2] = const TileModel(id: 2, value: 512);',
        '''p.setStateForTesting(board: [
        [null, const TileModel(id: 1, value: 512), const TileModel(id: 2, value: 512), null],
        [null, null, null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]);''');

    content = content.replaceAll(
        'p.board[0][0] = const TileModel(id: 1, value: 512);\n      p.board[0][1] = const TileModel(id: 2, value: 512);',
        '''p.setStateForTesting(board: [
        [const TileModel(id: 1, value: 512), const TileModel(id: 2, value: 512), null, null],
        [null, null, null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]);''');

    content = content.replaceAll(
        'provider.board = List.generate(4, (_) => List.filled(4, null));\n      provider.board[1][1] = const TileModel(id: 1, value: 2);',
        '''provider.setStateForTesting(board: [
        [null, null, null, null],
        [null, const TileModel(id: 1, value: 2), null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]);''');

    content = content.replaceAll(
        'provider.board = List.generate(4, (_) => List.filled(4, null));\n      provider.board[2][2] = const TileModel(id: 1, value: 2);\n      provider.board[2][3] = const TileModel(id: 2, value: 2);',
        '''provider.setStateForTesting(board: [
        [null, null, null, null],
        [null, null, null, null],
        [null, null, const TileModel(id: 1, value: 2), const TileModel(id: 2, value: 2)],
        [null, null, null, null],
      ]);''');

    content = content.replaceAll(
        'provider.isOver = false;\n      provider.score = 100;\n      provider.board = List.generate(4, (_) => List.filled(4, null));\n      provider.board[0][0] = const TileModel(id: 1, value: 2);',
        '''provider.setStateForTesting(isOver: false, score: 100, board: [
        [const TileModel(id: 1, value: 2), null, null, null],
        [null, null, null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]);''');

    content = content.replaceAll(
        'p.board[0][0] = const TileModel(id: 1, value: 2);\n      p.board[1][1] = const TileModel(id: 2, value: 4);',
        '''p.setStateForTesting(board: [
        [const TileModel(id: 1, value: 2), null, null, null],
        [null, const TileModel(id: 2, value: 4), null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]);''');

    File(file).writeAsStringSync(content);
  }
  stdout.writeln('Fixes applied successfully.');
}
