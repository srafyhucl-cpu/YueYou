/// 文本处理公共工具：章节检测、噪音过滤、标题清洗。
///
/// 所有涉及章节标题正则、噪音行正则、标题垃圾词正则的逻辑均集中于此，
/// 严禁在 reader_provider / file_import_service 等业务模块中重复定义。
class TextProcessing {
  TextProcessing._();

  /// 章节标题正则：匹配「第X章」「Chapter X」「引子」「序言」等模式。
  static final RegExp chapterTitleRegex = RegExp(
    r'^\s*(?:(?:正文|卷[0-9零一二三四五六七八九十百千两\s]+|.{0,4})\s*第?\s*[0-9零一二三四五六七八九十百千两]+\s*[章回节卷集部篇]|Chapter\s*[0-9]+|引子|序言|楔子|前言|内容简介|致读者)',
    caseSensitive: false,
  );

  /// 噪音词正则：独立出现的「正文」「VIP卷」「默认卷」等无意义行。
  static final RegExp noiseLineRegex = RegExp(
    r'^\s*(正文|正\s*文|正文卷|VIP卷|默认卷|上架感言|作品相关|\*{3,}|\-{3,}|={3,})\s*$',
    caseSensitive: false,
  );

  /// 标题清洗正则：移除标题中的垃圾前缀词（正文、VIP卷、默认卷）。
  static final RegExp titleGarbageRegex = RegExp(r'(正文|VIP卷|默认卷)');

  /// 判定给定文本是否为章节标题行。
  static bool isChapterTitle(String text) {
    return text.isNotEmpty && text.length < 50 && chapterTitleRegex.hasMatch(text);
  }

  /// 判定给定文本是否为噪音行（应跳过，不朗读不显示）。
  static bool isNoiseLine(String text) {
    if (text.isEmpty) return true;
    return noiseLineRegex.hasMatch(text);
  }

  /// 清洗章节标题：移除「正文」「VIP卷」等垃圾前缀。
  static String cleanChapterTitle(String raw) {
    return raw.replaceAll(titleGarbageRegex, '').trim();
  }

  /// 移除文件名中的 .txt 后缀（大小写不敏感）。
  static String stripTxtSuffix(String name) {
    return name.replaceAll(RegExp(r'\.txt$', caseSensitive: false), '');
  }
}
