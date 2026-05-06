import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:yueyou/core/constants/cyber_error_messages.dart';
import 'package:yueyou/core/utils/cyber_logger.dart';
import 'package:yueyou/core/utils/text_processing.dart';
import 'package:yueyou/features/library/domain/book_model.dart';

// V1.0 最大允许导入的文件大小（可配置常量）
const int kMaxFileSizeMb = 15;
const int _kMaxFileSizeBytes = kMaxFileSizeMb * 1024 * 1024;

/// 文件超过 V1.0 最大导入限制时抛出
class FileTooLargeException implements Exception {
  const FileTooLargeException();

  @override
  String toString() => CyberErrorMessages.importFileTooLarge(kMaxFileSizeMb);
}

// 导入结果数据类
class FileImportResult {
  final String title;
  final List<String> lines;
  final List<ChapterModel> chapters;

  const FileImportResult({
    required this.title,
    required this.lines,
    required this.chapters,
  });
}

// 章节提取 Isolate 参数包（传文件路径，不传字节数组）
class _ParseArgs {
  final String filePath;
  final String fileName;
  const _ParseArgs(this.filePath, this.fileName);
}

// 🔥 任务 2.1：重构导入服务
// - 弃用 compute，改用 Isolate.spawn 管理生命周期
// - 提供 cancelImport() 方法可在 dispose 时主动杀死 Isolate
class FileImportService {
  // 当前运行中的 Isolate 引用，用于主动杀死
  static Isolate? _activeIsolate;
  static int _activeImportToken = 0;

  // 是否有导入任务正在运行
  static bool get isImporting => _activeIsolate != null;

  // 原 importTxtFile：保留向后兼容，返回原始文本字符串
  static Future<String?> importTxtFile() async {
    final result = await importTxtFileStructured();
    if (result == null) return null;
    return result.lines.join('\n');
  }

  // 结构化导入：返回 lines + chapters + title
  static Future<FileImportResult?> importTxtFileStructured() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt'],
        allowMultiple: false,
        withData: false,
        lockParentWindow: true,
      );

      if (result == null || result.files.isEmpty) {
        return null;
      }

      final PlatformFile pickedFile = result.files.single;
      final String? filePath = pickedFile.path;
      if (filePath == null || filePath.isEmpty) {
        throw const FileSystemException(
          CyberErrorMessages.importReadPathFailed,
        );
      }

      final String fileName = pickedFile.name;

      // 🔥 Task 3：文件大小硬性校验，阻断超大文件撑爆内存
      final int fileSize = File(filePath).lengthSync();
      if (fileSize > _kMaxFileSizeBytes) {
        throw const FileTooLargeException();
      }

      // 🔥 2.1：只传文件路径给 Isolate，由 Isolate 内部流式读取
      return await _spawnParseIsolate(_ParseArgs(filePath, fileName));
    } catch (error, stackTrace) {
      if (error is FileTooLargeException) rethrow;
      CyberLogger.captureWarning(
        error,
        stack: stackTrace,
        tag: 'library',
        extra: {'context': 'TXT 文件导入失败'},
      );
      return null;
    }
  }

  // 🔥 核心：使用 Isolate.spawn + ReceivePort 管理生命周期
  static Future<FileImportResult?> _spawnParseIsolate(_ParseArgs args) async {
    final receivePort = ReceivePort();
    final int importToken = ++_activeImportToken;
    try {
      _activeIsolate = await Isolate.spawn(
        _isolateEntryPoint,
        _IsolateMessage(args: args, sendPort: receivePort.sendPort),
        debugName: 'TxtParseIsolate',
      );

      // 等待结果（Isolate 内部发送一次数据后退出）
      final dynamic rawResult = await receivePort.first;

      // Isolate 正常结束，释放引用
      if (_activeImportToken == importToken) {
        _activeIsolate = null;
      }

      if (_activeImportToken != importToken) {
        return null;
      }

      if (rawResult == null) return null;
      if (rawResult is! Map<String, dynamic>) return null;

      // 反序列化结果
      final title = rawResult['title'] as String;
      final lines = (rawResult['lines'] as List).cast<String>();
      final chapters = (rawResult['chapters'] as List)
          .cast<Map<String, dynamic>>()
          .map((c) => ChapterModel.fromJson(c))
          .toList();

      return FileImportResult(title: title, lines: lines, chapters: chapters);
    } catch (e, st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'library',
        extra: {'context': 'TXT 解析 Isolate 启动或结果接收失败'},
      );
      if (_activeImportToken == importToken) {
        _activeIsolate = null;
      }
      return null;
    } finally {
      receivePort.close();
    }
  }

  // Isolate 入口函数（async 以支持流式文件 I/O）
  static Future<void> _isolateEntryPoint(_IsolateMessage message) async {
    try {
      final result = await _parseFileStreaming(message.args);
      if (result == null) {
        message.sendPort.send(null);
        return;
      }
      // 序列化为原始 Map（Isolate 间不可直接传自定义类实例）
      message.sendPort.send(<String, dynamic>{
        'title': result.title,
        'lines': result.lines,
        'chapters': result.chapters.map((c) => c.toJson()).toList(),
      });
    } catch (e, stack) {
      CyberLogger.captureWarning(
        e,
        stack: stack,
        tag: 'library',
        extra: {'context': 'TXT 解析 Isolate 内部失败'},
      );
      message.sendPort.send(null);
    }
  }

  // 🔥 任务 2.1：主动取消导入（在页面 dispose 时调用）
  // 立即杀死后台 Isolate，释放 CPU 和内存
  static void cancelImport() {
    if (_activeIsolate != null) {
      CyberLogger.captureMessage('主动取消 TXT 导入 Isolate', tag: 'library');
      _activeImportToken++;
      _activeIsolate!.kill(priority: Isolate.immediate);
      _activeIsolate = null;
    }
  }

  static Future<FileImportResult?> parseFileForTesting(
    String filePath,
    String fileName,
  ) {
    return _parseFileStreaming(_ParseArgs(filePath, fileName));
  }

  static bool isValidUtf8SampleForTesting(Uint8List bytes) {
    return _isValidUtf8Sample(bytes);
  }

  static Uint8List stripUtf8BomForTesting(Uint8List bytes) {
    return _stripUtf8Bom(bytes);
  }

  // 🔥 2.1 核心：流式读取 + 解码 + 行切分，避免整文件驻留内存
  static Future<FileImportResult?> _parseFileStreaming(_ParseArgs args) async {
    try {
      final file = File(args.filePath);
      final title = TextProcessing.stripTxtSuffix(args.fileName);
      if (!await file.exists()) return null;

      // Step 1: 采样前 4KB 嗅探编码（只读采样量，不读全文件）
      final int fileLength = await file.length();
      final int sampleSize = min(4096, fileLength);
      final Uint8List sample;
      {
        final raf = file.openSync(mode: FileMode.read);
        try {
          sample = raf.readSync(sampleSize);
        } finally {
          raf.closeSync();
        }
      }

      final bool hasBom = sample.length >= 3 &&
          sample[0] == 0xEF &&
          sample[1] == 0xBB &&
          sample[2] == 0xBF;
      final Uint8List strippedSample = hasBom ? _stripUtf8Bom(sample) : sample;
      final bool useUtf8 = _isValidUtf8Sample(strippedSample);

      // Step 2: 流式读取，跳过 BOM 字节
      final Stream<List<int>> byteStream = file.openRead(hasBom ? 3 : 0);

      // Step 3: 流式解码 → 行切分
      final Stream<String> lineStream = byteStream
          .transform(
            useUtf8 ? const Utf8Decoder(allowMalformed: true) : gbk.decoder,
          )
          .transform(const LineSplitter());

      // Step 4: 逐行处理（trim + 去空行），内存中只驻留最终行列表
      final List<String> lines = [];
      await for (final line in lineStream) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          lines.add(trimmed);
        }
      }

      // Step 5: 章节提取（使用公共 TextProcessing 工具）
      final chapterRegex = TextProcessing.chapterTitleRegex;
      final noiseRegex = TextProcessing.noiseLineRegex;
      final garbageRegex = TextProcessing.titleGarbageRegex;

      final List<ChapterModel> chapters = [];
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (noiseRegex.hasMatch(line)) continue;
        if (line.length < 50 && chapterRegex.hasMatch(line)) {
          String cleanTitle = line.trim();
          cleanTitle = cleanTitle.replaceAll(garbageRegex, '').trim();
          if (cleanTitle.isEmpty) continue;
          chapters.add(ChapterModel(title: cleanTitle, lineIndex: i));
        }
      }

      return FileImportResult(title: title, lines: lines, chapters: chapters);
    } catch (e, st) {
      CyberLogger.captureWarning(
        e,
        stack: st,
        tag: 'library',
        extra: {'context': 'TXT 文件流式解析失败'},
      );
      return null;
    }
  }

  // 编码检测（采样模式）：允许尾部截断的不完整 UTF-8 序列
  static bool _isValidUtf8Sample(Uint8List bytes) {
    int i = 0;
    while (i < bytes.length) {
      final int byte = bytes[i];
      if (byte <= 0x7F) {
        i++;
        continue;
      }

      int expectedContinuation;
      if (byte >= 0xC2 && byte <= 0xDF) {
        expectedContinuation = 1;
      } else if (byte >= 0xE0 && byte <= 0xEF) {
        expectedContinuation = 2;
      } else if (byte >= 0xF0 && byte <= 0xF4) {
        expectedContinuation = 3;
      } else {
        return false;
      }

      // 采样模式：尾部截断视为有效（只是采样不完整，不代表编码错误）
      if (i + expectedContinuation >= bytes.length) {
        return true;
      }

      for (int j = 1; j <= expectedContinuation; j++) {
        final int continuation = bytes[i + j];
        if (continuation < 0x80 || continuation > 0xBF) {
          return false;
        }
      }

      if (byte == 0xE0 && bytes[i + 1] < 0xA0) return false;
      if (byte == 0xED && bytes[i + 1] > 0x9F) return false;
      if (byte == 0xF0 && bytes[i + 1] < 0x90) return false;
      if (byte == 0xF4 && bytes[i + 1] > 0x8F) return false;

      i += expectedContinuation + 1;
    }
    return true;
  }

  static Uint8List _stripUtf8Bom(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return Uint8List.sublistView(bytes, 3);
    }
    return bytes;
  }
}

// Isolate 消息包装（只能包含可序列化的数据 + SendPort）
class _IsolateMessage {
  final _ParseArgs args;
  final SendPort sendPort;
  const _IsolateMessage({required this.args, required this.sendPort});
}
