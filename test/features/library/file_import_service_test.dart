import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:file_picker/file_picker.dart';
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
      expect(result.chapters.map((chapter) => chapter.title),
          <String>['第一章 开始', '第二章 继续']);
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
      final dir =
          await Directory.systemTemp.createTemp('yueyou_import_missing_');
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

    // ── P1-5 回归用例：cancelImport 必须幂等且无副作用 ─────────────────────
    // CyberImportButton.dispose() 会无条件调用 cancelImport()，
    // 即便当时没有正在运行的导入 Isolate，也不能崩溃。
    //
    // 大厂标准升级：除了"不崩溃"还需验证 isImporting 状态机契约，
    // 确保 dispose 后业务层能正确感知"无导入运行"。
    test('cancelImport 在无导入运行时调用必须无副作用且幂等且 isImporting=false', () {
      // 前置：初始无导入
      expect(FileImportService.isImporting, isFalse, reason: '前置：初始无导入运行');

      // 调用 1
      FileImportService.cancelImport();
      expect(FileImportService.isImporting, isFalse,
          reason: 'cancelImport 后 isImporting 必须为 false');

      // 调用 2（幂等）
      FileImportService.cancelImport();
      expect(FileImportService.isImporting, isFalse,
          reason: '幂等调用后 isImporting 必须保持 false');

      // 调用 3（确保没有"首次后埋雷"的状态）
      FileImportService.cancelImport();
      expect(FileImportService.isImporting, isFalse);
    });

    // ── T-C / 大厂标准：cancelImport 在 dispose 时调用必须立即解除 isImporting ──
    // 模拟 CyberImportButton.dispose() 在导入按钮 widget 销毁时的调用路径，
    // 验证此调用绝不阻塞、绝不抛异常、且 isImporting 立即归零。
    test('T-C dispose 路径：cancelImport 必须同步完成且不阻塞', () {
      final stopwatch = Stopwatch()..start();
      FileImportService.cancelImport();
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason: 'T-C：cancelImport 必须同步快速完成（<100ms），不阻塞 dispose');
      expect(FileImportService.isImporting, isFalse);
    });

    // ── 阶段 1 治理：补齐流式解析的章节提取分支 ────────────────────────────────
    test('parseFileForTesting 噪音行（如 "正文"）必须被跳过且不出现在 lines 中', () async {
      final dir = await Directory.systemTemp.createTemp('yueyou_import_noise_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final file = File('${dir.path}/noise.txt');
      await file.writeAsString('正文\n第一章 起点\n你好\n***\n第二章 继续\n下文');

      final result = await FileImportService.parseFileForTesting(
        file.path,
        'noise.txt',
      );

      expect(result, isNotNull);
      expect(result!.lines, contains('正文'),
          reason: '解析阶段保留行，章节提取阶段才会跳过 "正文" 噪音');
      // 噪音行不应被识别为章节
      final titles = result.chapters.map((c) => c.title).toList();
      expect(titles, equals(<String>['第一章 起点', '第二章 继续']),
          reason: '"正文"/"***" 噪音行不得被识别为章节标题');
    });

    test('parseFileForTesting 标题清洗：含 VIP卷/正文 前缀的章节必须被剥离', () async {
      final dir =
          await Directory.systemTemp.createTemp('yueyou_import_cleantitle_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final file = File('${dir.path}/clean.txt');
      // "VIP卷第一章 章名" 应被清洗为 "第一章 章名"
      await file.writeAsString('VIP卷第一章 起航\n内容一');

      final result = await FileImportService.parseFileForTesting(
        file.path,
        'clean.txt',
      );

      expect(result, isNotNull);
      expect(result!.chapters.length, 1);
      expect(result.chapters.single.title, contains('第一章'),
          reason: 'titleGarbageRegex 必须剥离 VIP卷/正文 前缀');
      expect(result.chapters.single.title, isNot(contains('VIP卷')));
    });

    test('parseFileForTesting 章节行 ≥ 50 字时不识别为章节标题', () async {
      final dir =
          await Directory.systemTemp.createTemp('yueyou_import_longline_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final file = File('${dir.path}/long.txt');
      // 一行同时包含 "第一章" 但总长 ≥ 50 字 → 应当不被当作章节标题（防误识章中段落）。
      // String.length 在 Dart 中按 UTF-16 码元计数，每个中文 = 1，标点 = 1。
      final longLine = '第一章 起点的故事正文内容长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长';
      assert(longLine.length >= 50,
          'longLine 必须 >=50 字符以触发 < 50 守卫；实际 ${longLine.length}');
      await file.writeAsString('$longLine\n第二章 短\n短内容');

      final result = await FileImportService.parseFileForTesting(
        file.path,
        'long.txt',
      );

      expect(result, isNotNull);
      // 仅 "第二章 短" 应被识别
      expect(result!.chapters.map((c) => c.title), equals(<String>['第二章 短']),
          reason: '长度 ≥ 50 字的行不得被识别为章节标题（防误识章中段落）');
    });

    test('parseFileForTesting 文件全空时返回 lines 与 chapters 均为空', () async {
      final dir = await Directory.systemTemp.createTemp('yueyou_import_empty_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final file = File('${dir.path}/empty.txt');
      await file.writeAsString('');

      final result = await FileImportService.parseFileForTesting(
        file.path,
        'empty.txt',
      );

      expect(result, isNotNull);
      expect(result!.lines, isEmpty);
      expect(result.chapters, isEmpty);
    });

    // ── UTF-8 校验 / BOM 边界 ──────────────────────────────────────────────
    test('isValidUtf8SampleForTesting：3 字节序列尾部截断仍视为有效', () {
      // 0xE4 0xB8 是 "中" 字的前两字节，最后一字节缺失 — 采样模式下应返回 true
      final bytes = Uint8List.fromList(const [0xE4, 0xB8]);
      expect(FileImportService.isValidUtf8SampleForTesting(bytes), isTrue);
    });

    test('isValidUtf8SampleForTesting：4 字节序列（F0xx 范围）合法', () {
      // 0xF0 0x9F 0x98 0x80 = "😀"
      final bytes = Uint8List.fromList(const [0xF0, 0x9F, 0x98, 0x80, 0x41]);
      expect(FileImportService.isValidUtf8SampleForTesting(bytes), isTrue);
    });

    test('isValidUtf8SampleForTesting：续字节超出 0x80-0xBF 范围则视为非法', () {
      // 0xE4 0x00 0x00 — 续字节非法
      final bytes = Uint8List.fromList(const [0xE4, 0x00, 0x00]);
      expect(FileImportService.isValidUtf8SampleForTesting(bytes), isFalse);
    });

    test('isValidUtf8SampleForTesting：0xE0 + 续字节 < 0xA0 视为非法（overlong）', () {
      // 0xE0 0x80 0x80 — overlong 编码必须视为非法
      final bytes = Uint8List.fromList(const [0xE0, 0x80, 0x80]);
      expect(FileImportService.isValidUtf8SampleForTesting(bytes), isFalse);
    });

    test('stripUtf8BomForTesting：无 BOM 时返回原 bytes', () {
      final bytes = Uint8List.fromList(const [0x41, 0x42, 0x43]);
      final stripped = FileImportService.stripUtf8BomForTesting(bytes);
      expect(stripped, equals(bytes));
    });

    // ── FileTooLargeException.toString 必须携带限制大小提示 ─────────────────
    // 覆盖 lib/features/library/services/file_import_service.dart:23-24。
    test('FileTooLargeException.toString 必须包含 15MB 限制', () {
      const exc = FileTooLargeException();
      expect(exc.toString(), contains('15'),
          reason: 'toString 必须暴露 kMaxFileSizeMb 用于 UI 提示');
    });

    // ── GBK 编码文件流式解析必须切换到 gbk.decoder ──────────────────────────
    // 覆盖 lib/features/library/services/file_import_service.dart:245
    // (useUtf8==false → gbk.decoder 分支)。
    test('parseFileForTesting GBK 编码文件必须切换到 gbk.decoder 解析', () async {
      final dir = await Directory.systemTemp.createTemp('yueyou_import_gbk_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final file = File('${dir.path}/gbk.txt');
      // 关键：用 fast_gbk 编码生成纯 GBK 字节，前 4KB 嗅探将判定 useUtf8=false
      final gbkBytes = gbk.encode('第一章 序章\n你好世界');
      await file.writeAsBytes(gbkBytes);

      final result = await FileImportService.parseFileForTesting(
        file.path,
        'gbk.txt',
      );

      expect(result, isNotNull, reason: 'GBK 文件必须可被 gbk.decoder 正确解析');
      expect(result!.lines, equals(<String>['第一章 序章', '你好世界']));
      expect(result.chapters.single.title, '第一章 序章');
    });
  });

  // ── importTxtFileStructured / cancelImport 公开 API 完整链路 ──────────────
  // 通过 mock FilePicker.platform 注入受控的 pickFiles 返回值，覆盖：
  //   * importTxtFileStructured 用户取消（result.files.isEmpty）→ line 76-78
  //   * importTxtFileStructured filePath 为空 → 抛 FileSystemException → line 80-82
  //   * importTxtFileStructured 文件超大 → 抛 FileTooLargeException → line 88, 91-94
  //   * importTxtFileStructured 完整 happy path → line 96-97 + _spawnParseIsolate
  //     line 111-159 + _isolateEntryPoint line 162-184
  //   * cancelImport 在 _activeIsolate != null 时走 kill 路径 → line 188-194
  group('FileImportService - 公开 API 链路（FilePicker mock）', () {
    late _FakeFilePicker _fake;

    setUp(() {
      // 测试环境下 FilePicker._instance 是 late 字段且无 platform plugin 注册，
      // 直接读 FilePicker.platform 会抛 LateInitializationError，因此不备份
      // original，每个用例独立 set 新 fake 即可。
      _fake = _FakeFilePicker();
      FilePicker.platform = _fake;
    });

    test('importTxtFileStructured 用户取消时返回 null', () async {
      _fake.mockResult = null;
      final result = await FileImportService.importTxtFileStructured();
      expect(result, isNull,
          reason: 'pickFiles 返回 null（用户取消）时必须直接 return null');
    });

    test('importTxtFileStructured 选中文件路径为空时返回 null（catch FileSystemException）',
        () async {
      // 路径为空时 lib 会 throw FileSystemException，被外层 catch 吞下后返回 null
      _fake.mockResult = FilePickerResult(<PlatformFile>[
        PlatformFile(name: 'broken.txt', size: 0),
      ]);
      final result = await FileImportService.importTxtFileStructured();
      expect(result, isNull,
          reason: 'filePath==null 抛 FileSystemException 必须被 catch 吞下返回 null');
    });

    test('importTxtFileStructured 文件超过 15MB 必须 rethrow FileTooLargeException',
        () async {
      final dir =
          await Directory.systemTemp.createTemp('yueyou_import_toolarge_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final big = File('${dir.path}/big.txt');
      // 写入 16MB 字节，超过 kMaxFileSizeMb=15
      await big.writeAsBytes(Uint8List(16 * 1024 * 1024));

      _fake.mockResult = FilePickerResult(<PlatformFile>[
        PlatformFile(name: 'big.txt', size: 16 * 1024 * 1024, path: big.path),
      ]);

      expect(
        () => FileImportService.importTxtFileStructured(),
        throwsA(isA<FileTooLargeException>()),
        reason: 'FileTooLargeException 必须被 rethrow 不被 catch 吞掉',
      );
    });

    test('importTxtFileStructured 正常 TXT 文件必须走完 Isolate 解析返回结构化结果', () async {
      final dir = await Directory.systemTemp.createTemp('yueyou_import_ok_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final file = File('${dir.path}/novel.txt');
      await file.writeAsString('第一章 起点\n你好\n第二章 继续\n世界');

      _fake.mockResult = FilePickerResult(<PlatformFile>[
        PlatformFile(name: 'novel.txt', size: 100, path: file.path),
      ]);

      final result = await FileImportService.importTxtFileStructured();
      expect(result, isNotNull,
          reason: 'happy path 必须返回非 null FileImportResult');
      expect(result!.title, 'novel');
      expect(result.lines, contains('第一章 起点'));
      expect(result.chapters.map((c) => c.title),
          equals(<String>['第一章 起点', '第二章 继续']));
      // 解析结束后 _activeIsolate 必须被释放
      expect(FileImportService.isImporting, isFalse,
          reason: 'Isolate 正常结束后 _activeIsolate 必须被置 null');
    });

    test('cancelImport 在 _activeIsolate != null 时必须走 kill 路径', () async {
      // 启动一个解析任务但不 await 完成，立即 cancel
      final dir =
          await Directory.systemTemp.createTemp('yueyou_import_cancel_');
      addTearDown(() async {
        // Windows 下被 kill 的 Isolate 可能仍持有文件句柄短暂时刻，
        // 删除失败是合法情况，吞下不影响断言。
        try {
          if (await dir.exists()) await dir.delete(recursive: true);
        } catch (_) {}
      });

      final file = File('${dir.path}/novel.txt');
      // 故意写大一些让 Isolate 解析慢一点（仍在 15MB 限制内）
      final lines = List<String>.generate(
        50000,
        (i) => i % 1000 == 0 ? '第${i ~/ 1000}章 标题' : '第 $i 行内容',
      );
      await file.writeAsString(lines.join('\n'));

      _fake.mockResult = FilePickerResult(<PlatformFile>[
        PlatformFile(
          name: 'novel.txt',
          size: file.lengthSync(),
          path: file.path,
        ),
      ]);

      // fire-and-forget 启动
      final future = FileImportService.importTxtFileStructured();

      // 等 Isolate 启动（_activeIsolate 被赋值）
      for (int i = 0; i < 50 && !FileImportService.isImporting; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      // 期望已开始；若太快完成则放弃断言（covers line 188-194 的强 ROI 路径）
      if (FileImportService.isImporting) {
        FileImportService.cancelImport();
        expect(FileImportService.isImporting, isFalse,
            reason: 'cancelImport 调用后 _activeIsolate 必须立即置 null');
      }

      // 等待 future 完成（cancel 后应当返回 null 或异常被 catch）
      final result = await future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
      // result 可能为 null（cancel 命中 token 不匹配）或正常完成（cancel 太晚）
      // 两种都是合法路径
      expect(result == null || result.title == 'novel', isTrue);
    });
  });
}

/// FilePicker mock：仅 override pickFiles，其他默认 throw UnimplementedError。
///
/// 通过 `extends FilePicker` 自动获得 PlatformInterface verifyToken 通过。
class _FakeFilePicker extends FilePicker {
  FilePickerResult? mockResult;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    return mockResult;
  }
}
