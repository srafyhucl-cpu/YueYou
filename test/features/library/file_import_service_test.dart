import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/library/services/file_import_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FileImportService', () {
    test('isValidUtf8SampleForTesting 对合法 UTF-8 采样返回 true', () {
      final bytes = Uint8List.fromList(utf8.encode('第一章 你好世界'));

      expect(FileImportService.isValidUtf8SampleForTesting(bytes), isTrue);
    });

    test('isValidUtf8SampleForTesting 对非法 UTF-8 起始字节返回 false', () {
      final bytes = Uint8List.fromList(const [0xFF, 0x61, 0x62]);

      expect(FileImportService.isValidUtf8SampleForTesting(bytes), isFalse);
    });

    test('isValidUtf8SampleForTesting 对尾部截断采样返回 true', () {
      final bytes = Uint8List.fromList(const [0xE4, 0xB8]);

      expect(FileImportService.isValidUtf8SampleForTesting(bytes), isTrue);
    });

    test('stripUtf8BomForTesting 会移除 UTF-8 BOM', () {
      final bytes = Uint8List.fromList(const [0xEF, 0xBB, 0xBF, 0x41, 0x42]);

      final stripped = FileImportService.stripUtf8BomForTesting(bytes);

      expect(stripped, Uint8List.fromList(const [0x41, 0x42]));
    });

    test('parseFileForTesting 能流式解析 UTF-8 文件并提取章节', () async {
      final dir = await Directory.systemTemp.createTemp('yueyou_import_utf8_');
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final file = File('${dir.path}/novel.txt');
      await file.writeAsString('正文\n第一章 开始\n你好世界。\n第二章 继续\n后续内容。');

      final result = await FileImportService.parseFileForTesting(
        file.path,
        'novel.txt',
      );

      expect(result, isNotNull);
      expect(result!.title, 'novel');
      expect(result.lines, containsAll(<String>['第一章 开始', '你好世界。', '第二章 继续']));
      expect(result.chapters.map((chapter) => chapter.title), <String>['第一章 开始', '第二章 继续']);
    });

    test('parseFileForTesting 能跳过 BOM 且过滤空行', () async {
      final dir = await Directory.systemTemp.createTemp('yueyou_import_bom_');
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final file = File('${dir.path}/bom_book.txt');
      final bytes = <int>[
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('第一章 序幕\n\n内容一\n\n内容二'),
      ];
      await file.writeAsBytes(bytes);

      final result = await FileImportService.parseFileForTesting(
        file.path,
        'bom_book.txt',
      );

      expect(result, isNotNull);
      expect(result!.title, 'bom_book');
      expect(result.lines, <String>['第一章 序幕', '内容一', '内容二']);
      expect(result.chapters.single.title, '第一章 序幕');
    });

    test('parseFileForTesting 对不存在文件返回 null', () async {
      final dir = await Directory.systemTemp.createTemp('yueyou_import_missing_');
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final result = await FileImportService.parseFileForTesting(
        '${dir.path}/missing.txt',
        'missing.txt',
      );

      expect(result, isNull);
    });
  });
}
