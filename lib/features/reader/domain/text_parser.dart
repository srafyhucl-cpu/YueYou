import 'dart:isolate';
import '../../../core/utils/safe_string.dart';

/// 解析结果：句子列表 + 每句对应的原始行号
class ParseResult {
  final List<String> sentences;

  /// rawLineOrigins[i] = 产生 sentences[i] 的原始行号
  final List<int> rawLineOrigins;
  const ParseResult(this.sentences, this.rawLineOrigins);
}

/// 赛博文本解析引擎
/// 职责：在独立 Isolate 中清洗百万级文本，执行语义切分与防溢出截断
class TextParser {
  /// 主解析入口：使用 Isolate.run (通过 compute 封装) 确保解析过程不卡顿 UI
  static Future<ParseResult> parse(String rawText) async {
    return Isolate.run(() => _internalParse(rawText));
  }

  /// 内部原子解析逻辑（运行在独立线程）
  static ParseResult _internalParse(String text) {
    if (text.trim().isEmpty) return const ParseResult([], []);

    // 0. 预清洗：碾压所有连续点、全角句号、省略号为单个句号
    text = text.replaceAll(RegExp(r'[。\.…]{2,}'), '。');

    // 1. 预处理：按换行符拆分，过滤空白行，去除首尾冗余空格
    final rawLines = text.split(RegExp(r'\r?\n')).toList();

    final List<String> sentences = [];
    final List<int> rawLineOrigins = [];

    // 2. 高级正则切片：按中文标点符号进行精准切分，并保留标点
    // 正则解释：匹配句号、叹号、问号、分号及省略号的后位置（零宽后行断言）
    final splitReg = RegExp(r'(?<=[。！？；…])');

    for (int rawIdx = 0; rawIdx < rawLines.length; rawIdx++) {
      final line = rawLines[rawIdx].trim();
      if (line.isEmpty) continue;

      final segments = line.split(splitReg);
      for (var segment in segments) {
        final clean = segment.trim();
        if (clean.isEmpty) {
          continue;
        }

        // 过滤纯标点/引号/括号句（无汉字、字母、数字），如切分后残留的 "、」、》等
        if (!RegExp(r'[\u4e00-\u9fff\u3400-\u4dbf\w]').hasMatch(clean)) {
          continue;
        }

        // 3. 防溢出机制：如果切分后某一句仍然超过 50 个字符（极长无标点句），必须在空格或逗号处进行强制二次截断
        if (clean.length > 50) {
          final splits = _emergencySplit(clean, 50);
          for (final s in splits) {
            sentences.add(s);
            rawLineOrigins.add(rawIdx);
          }
        } else {
          sentences.add(clean);
          rawLineOrigins.add(rawIdx);
        }
      }
    }

    return ParseResult(sentences, rawLineOrigins);
  }

  /// 二次截断算法：优先寻找语义停顿点（逗号、空格、顿号、逗号）
  /// 确保 UI 在有限宽度内不会溢出，同时保持阅读节奏
  ///
  /// 断点优先级（两遍扫描）：
  /// 1. 强断点 — 标点符号与空格（，, 、 \s）
  /// 2. 软断点 — 连词/语气助词（的、了、和、与），避免劈开词组导致 TTS 朗读怪异
  /// 3. 兜底 — 强制物理截断
  static List<String> _emergencySplit(String longText, int limit) {
    final List<String> chunks = [];
    int start = 0;

    while (start < longText.length) {
      final int end = start + limit;
      if (end >= longText.length) {
        chunks.add(safeSubstring(longText, start, longText.length));
        break;
      }

      final sub = safeSubstring(longText, start, end);

      // 第一遍：寻找强断点（标点、空格、顿号）
      int lastBreak = sub.lastIndexOf(RegExp(r'[，, 、\s]'));

      // 第二遍：若无合理强断点，尝试软断点（连词/语气助词）
      if (lastBreak == -1 || lastBreak <= limit * 0.7) {
        final softBreak = sub.lastIndexOf(RegExp(r'[的了和与]'));
        if (softBreak != -1 && softBreak > limit * 0.5) {
          lastBreak = softBreak;
        }
      }

      // 如果断点位置合理，则在此处截断；否则强制物理截断
      if (lastBreak != -1 && lastBreak > limit * 0.5) {
        chunks.add(safeSubstring(longText, start, start + lastBreak + 1));
        start += lastBreak + 1;
      } else {
        chunks.add(safeSubstring(longText, start, end));
        start = end;
      }
    }
    return chunks;
  }
}
