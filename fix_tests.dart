import 'dart:io';

void main() {
  final files = [
    'test/features/game_2048/game_provider_test.dart',
    'test/features/game_2048/square_board_test.dart',
  ];

  for (final file in files) {
    var content = File(file).readAsStringSync();

    // 替换 p.board = List.generate(...)
    content = content.replaceAllMapped(
        RegExp(
            r'p\.board\s*=\s*List\.generate\([^;]+;\s*p\.board\[0\]\[0\]\s*=\s*(const TileModel\([^)]+\));\s*p\.board\[1\]\[1\]\s*=\s*(const TileModel\([^)]+\));'),
        (match) => '''p.setStateForTesting(board: [
        [\${match[1]}, null, null, null],
        [null, \${match[2]}, null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]);''');

    // 替换 p.board[0][1] = ...; p.board[0][2] = ...;
    content = content.replaceAllMapped(
        RegExp(
            r'p\.board\[0\]\[1\]\s*=\s*(const TileModel\([^)]+\));\s*p\.board\[0\]\[2\]\s*=\s*(const TileModel\([^)]+\));'),
        (match) => '''p.setStateForTesting(board: [
        [null, \${match[1]}, \${match[2]}, null],
        [null, null, null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]);''');

    // 替换 p.board[0][0] = ...; p.board[0][1] = ...;
    content = content.replaceAllMapped(
        RegExp(
            r'p\.board\[0\]\[0\]\s*=\s*(const TileModel\([^)]+\));\s*p\.board\[0\]\[1\]\s*=\s*(const TileModel\([^)]+\));'),
        (match) => '''p.setStateForTesting(board: [
        [\${match[1]}, \${match[2]}, null, null],
        [null, null, null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]);''');

    // 替换 square_board_test 的赋值
    content = content.replaceAllMapped(
        RegExp(
            r'provider\.board\s*=\s*List\.generate\([^;]+;\s*provider\.board\[1\]\[1\]\s*=\s*(const TileModel\([^)]+\));'),
        (match) => '''provider.setStateForTesting(board: [
        [null, null, null, null],
        [null, \${match[1]}, null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]);''');

    content = content.replaceAllMapped(
        RegExp(
            r'provider\.board\s*=\s*List\.generate\([^;]+;\s*provider\.board\[2\]\[2\]\s*=\s*(const TileModel\([^)]+\));\s*provider\.board\[2\]\[3\]\s*=\s*(const TileModel\([^)]+\));'),
        (match) => '''provider.setStateForTesting(board: [
        [null, null, null, null],
        [null, null, null, null],
        [null, null, \${match[1]}, \${match[2]}],
        [null, null, null, null],
      ]);''');

    content = content.replaceAllMapped(
        RegExp(
            r'provider\.isOver\s*=\s*(true|false);\s*provider\.score\s*=\s*(\d+);\s*provider\.board\s*=\s*List\.generate\([^;]+;'),
        (match) =>
            'provider.setStateForTesting(isOver: \${match[1]}, score: \${match[2]});');

    content = content.replaceAll(RegExp(r'provider\.isOver\s*=\s*true;'),
        'provider.setStateForTesting(isOver: true);');

    File(file).writeAsStringSync(content);
  }
  print("Fix applied.");
}
