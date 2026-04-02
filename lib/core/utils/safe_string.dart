// 全局字符串安全截取工具
// 任务 1.4：防止 Emoji / 特殊字符导致 RangeError 红屏

// 安全截取字符串，内部使用 .clamp() 确保索引不越界
// [text] 要截取的原始字符串
// [start] 起始索引（含）
// [end] 结束索引（不含）
String safeSubstring(String text, int start, int end) {
  if (text.isEmpty) return '';
  final int safeStart = start.clamp(0, text.length);
  final int safeEnd = end.clamp(safeStart, text.length);
  return text.substring(safeStart, safeEnd);
}
