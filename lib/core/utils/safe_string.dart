extension SafeStringExtension on String {
  /// 安全截取字符串，内部使用 .clamp() 确保索引不越界
  /// [start] 起始索引（含）
  /// [end] 结束索引（不含）
  String safeSubstring(int start, int end) {
    if (isEmpty) return '';
    final int safeStart = start.clamp(0, length);
    final int safeEnd = end.clamp(safeStart, length);
    return substring(safeStart, safeEnd);
  }
}
