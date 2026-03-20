import 'package:flutter/foundation.dart';

/// 赛博文本解析引擎
/// 职责：在独立 Isolate 中清洗百万级文本，执行语义切分与防溢出截断
class TextParser {
  /// 主解析入口：使用 Isolate.run (通过 compute 封装) 确保解析过程不卡顿 UI
  static Future<List<String>> parse(String rawText) async {
    return await compute(_internalParse, rawText);
  }

  /// 内部原子解析逻辑（运行在独立线程）
  static List<String> _internalParse(String text) {
    if (text.trim().isEmpty) return [];

    // 0. 预清洗：碾压所有连续点、全角句号、省略号为单个句号
    text = text.replaceAll(RegExp(r'[。\.…]{2,}'), '。');

    // 1. 预处理：按换行符拆分，过滤空白行，去除首尾冗余空格
    final lines = text
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .map((l) => l.trim());

    final List<String> sentences = [];

    // 2. 高级正则切片：按中文标点符号进行精准切分，并保留标点
    // 正则解释：匹配句号、叹号、问号、分号及省略号的后位置（零宽后行断言）
    final splitReg = RegExp(r'(?<=[。！？；…])');

    for (var line in lines) {
      final segments = line.split(splitReg);
      for (var segment in segments) {
        final clean = segment.trim();
        if (clean.isEmpty) continue;

        // 3. 防溢出机制：如果切分后某一句仍然超过 50 个字符（极长无标点句），必须在空格或逗号处进行强制二次截断
        if (clean.length > 50) {
          sentences.addAll(_emergencySplit(clean, 50));
        } else {
          sentences.add(clean);
        }
      }
    }

    return sentences;
  }

  /// 二次截断算法：优先寻找语义停顿点（逗号、空格、顿号、逗号）
  /// 确保 UI 在有限宽度内不会溢出，同时保持阅读节奏
  static List<String> _emergencySplit(String longText, int limit) {
    final List<String> chunks = [];
    int start = 0;

    while (start < longText.length) {
      int end = start + limit;
      if (end >= longText.length) {
        chunks.add(longText.substring(start));
        break;
      }

      // 在阈值范围内寻找最佳断点
      final sub = longText.substring(start, end);
      // 匹配中英文逗号、空格、顿号
      int lastBreak = sub.lastIndexOf(RegExp(r'[，, 、\s]'));

      // 如果断点位置合理（超过阈值的 70%），则在此处截断；否则强制物理截断
      if (lastBreak != -1 && lastBreak > limit * 0.7) {
        chunks.add(longText.substring(start, start + lastBreak + 1));
        start += lastBreak + 1;
      } else {
        chunks.add(longText.substring(start, end));
        start = end;
      }
    }
    return chunks;
  }
}
