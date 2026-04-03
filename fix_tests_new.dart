import 'dart:io';

void main() {
  final files = [
    'test/features/game_2048/game_provider_test.dart',
    'test/features/game_2048/square_board_test.dart',
  ];

  for (final file in files) {
    var content = File(file).readAsStringSync();
    
    content = content.replaceAllMapped(
      RegExp(r'p\.board\s*=\s*List\.generate\([^;]+;\s*p\.board\[0\]\[0\]\s*=\s*(const TileModel\([^)]+\));\s*p\.board\[1\]\[1\]\s*=\s*(const TileModel\([^)]+\));'),
      (match) => '''p.setStateForTesting(board: [
        [''' + match.group(1)! + ''', null, null, null],
        [null, ''' + match.group(2)! + ''', null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]);'''
    );
    
    content = content.replaceAllMapped(
      RegExp(r'p\.board\[0\]\[1\]\s*=\s*(const TileModel\([^)]+\));\s*p\.board\[0\]\[2\]\s*=\s*(const TileModel\([^)]+\));'),
      (match) => '''p.setStateForTesting(board: [
        [null, ''' + match.group(1)! + ''', ''' + match.group(2)! + ''', null],
        [null, null, null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]);'''
    );
    
    content = content.replaceAllMapped(
      RegExp(r'p\.board\[0\]\[0\]\s*=\s*(const TileModel\([^)]+\));\s*p\.board\[0\]\[1\]\s*=\s*(const TileModel\([^)]+\));'),
      (match) => '''p.setStateForTesting(board: [
        [''' + match.group(1)! + ''', ''' + match.group(2)! + ''', null, null],
        [null, null, null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]);'''
    );

    // 对于一些直接赋值的 p.board = [ ... ]; 换成 setStateForTesting
    content = content.replaceAllMapped(
      RegExp(r'p\.board\s*=\s*(\[[^;]+\]);', multiLine: true),
      (match) => 'p.setStateForTesting(board: ' + match.group(1)! + ');'
    );

    content = content.replaceAllMapped(
      RegExp(r'provider\.board\s*=\s*List\.generate\([^;]+;\s*provider\.board\[1\]\[1\]\s*=\s*(const TileModel\([^)]+\));'),
      (match) => '''provider.setStateForTesting(board: [
        [null, null, null, null],
        [null, ''' + match.group(1)! + ''', null, null],
        [null, null, null, null],
        [null, null, null, null],
      ]);'''
    );
    
    content = content.replaceAllMapped(
      RegExp(r'provider\.board\s*=\s*List\.generate\([^;]+;\s*provider\.board\[2\]\[2\]\s*=\s*(const TileModel\([^)]+\));\s*provider\.board\[2\]\[3\]\s*=\s*(const TileModel\([^)]+\));'),
      (match) => '''provider.setStateForTesting(board: [
        [null, null, null, null],
        [null, null, null, null],
        [null, null, ''' + match.group(1)! + ''', ''' + match.group(2)! + '''],
        [null, null, null, null],
      ]);'''
    );

    content = content.replaceAllMapped(
      RegExp(r'provider\.isOver\s*=\s*(true|false);\s*provider\.score\s*=\s*(\d+);\s*provider\.board\s*=\s*(\[[^;]+\]);', multiLine: true),
      (match) => 'provider.setStateForTesting(isOver: ' + match.group(1)! + ', score: ' + match.group(2)! + ', board: ' + match.group(3)! + ');'
    );

    content = content.replaceAllMapped(
      RegExp(r'provider\.isOver\s*=\s*(true|false);'),
      (match) => 'provider.setStateForTesting(isOver: ' + match.group(1)! + ');'
    );

    File(file).writeAsStringSync(content);
  }
  print("Fix applied.");
}
