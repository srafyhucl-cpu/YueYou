import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:yueyou/features/library/domain/book_model.dart';

/// 导入结果数据类
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

/// 章节提取 Isolate 参数包
class _ParseArgs {
  final Uint8List bytes;
  final String fileName;
  const _ParseArgs(this.bytes, this.fileName);
}

class FileImportService {
  /// 原 importTxtFile：保留向后兼容，返回原始文本字符串
  static Future<String?> importTxtFile() async {
    final result = await importTxtFileStructured();
    if (result == null) return null;
    return result.lines.join('\n');
  }

  /// 结构化导入：返回 lines + chapters + title
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
        throw const FileSystemException('无法读取所选 TXT 文件路径');
      }

      final Uint8List rawBytes = await File(filePath).readAsBytes();
      final String fileName = pickedFile.name;
      return await compute(_parseFile, _ParseArgs(rawBytes, fileName));
    } catch (error, stackTrace) {
      debugPrint(' TXT 导入失败: $error\n$stackTrace');
      return null;
    }
  }

  /// Isolate-safe 核心解析入口 —— 对应 JS fileInput.change 回调全流程
  static FileImportResult? _parseFile(_ParseArgs args) {
    try {
      final String? text = _decodeBytes(args.bytes);
      if (text == null) return null;

      final String title =
          args.fileName.replaceAll(RegExp(r'\.txt$', caseSensitive: false), '');

      // 对应 JS: rawLines = text.split(/\r?\n/).map(l => l.trim()).filter(l => l.length > 0)
      final List<String> lines = text
          .split(RegExp(r'\r?\n'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      // 对应 JS chapterRegex + line.length < 50 限制
      final RegExp chapterRegex = RegExp(
        r'^\s*(?:(?:正文|卷[0-9零一二三四五六七八九十百千两\s]+|.{0,4})\s*第?\s*[0-9零一二三四五六七八九十百千两]+\s*[章回节卷集部篇]|Chapter\s*[0-9]+|引子|序言|楔子|前言|内容简介|致读者)',
        caseSensitive: false,
      );
      final List<ChapterModel> chapters = [];
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].length < 50 && chapterRegex.hasMatch(lines[i])) {
          chapters.add(ChapterModel(title: lines[i].trim(), lineIndex: i));
        }
      }

      return FileImportResult(title: title, lines: lines, chapters: chapters);
    } catch (e, st) {
      debugPrint('FileImportService._parseFile error: $e\n$st');
      return null;
    }
  }

  static String? _decodeBytes(Uint8List bytes) {
    try {
      final Uint8List sanitizedBytes = _stripUtf8Bom(bytes);
      if (sanitizedBytes.isEmpty) return '';

      // 🛡️ 第一重盾：严格的 UTF-8 校验
      try {
        return const Utf8Decoder(allowMalformed: false).convert(sanitizedBytes);
      } catch (_) {
        // 🛡️ 第二重盾：GBK 容错推土机
        try {
          return gbk.decode(sanitizedBytes, allowMalformed: true);
        } catch (_) {
          // 🛡️ 第三重盾：宽容 UTF-8 强解
          return const Utf8Decoder(allowMalformed: true)
              .convert(sanitizedBytes);
        }
      }
    } catch (error, stackTrace) {
      debugPrint(' TXT 编码解析彻底崩塌: $error\n$stackTrace');
      return null;
    }
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
