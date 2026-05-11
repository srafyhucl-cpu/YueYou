/// 阅游单文件体量阈值常量。
///
/// 单一来源：`.windsurf/rules/AGENT.md` 红线第 8 条 / `CLAUDE.md`
/// 同名章节 / `.agents/skills/yueyou-file-size-guard/SKILL.md`。
///
/// 修改任何阈值时，必须同步更新上述三个文档，避免规则漂移。
class FileSizeThreshold {
  /// 层级路径片段（用 `/` 形式，便于在跨平台规范化路径上匹配）。
  final String pathLabel;

  /// 警戒线：达到即输出 warning，不得继续在该文件追加新职责。
  final int warning;

  /// 硬上限：达到即输出 blocking，必须拆分。
  final int blocking;

  const FileSizeThreshold({
    required this.pathLabel,
    required this.warning,
    required this.blocking,
  });
}

/// 各层级文件体量阈值，与 AGENT.md / CLAUDE.md / SKILL.md 单一来源对齐。
const FileSizeThreshold kServicesThreshold = FileSizeThreshold(
  pathLabel: 'lib/features/*/services/',
  warning: 600,
  blocking: 800,
);

const FileSizeThreshold kProvidersThreshold = FileSizeThreshold(
  pathLabel: 'lib/features/*/providers/',
  warning: 700,
  blocking: 900,
);

const FileSizeThreshold kPresentationThreshold = FileSizeThreshold(
  pathLabel: 'lib/features/*/presentation/',
  warning: 900,
  blocking: 1100,
);

const FileSizeThreshold kDomainThreshold = FileSizeThreshold(
  pathLabel: 'lib/features/*/domain/',
  warning: 500,
  blocking: 700,
);

const FileSizeThreshold kCoreThreshold = FileSizeThreshold(
  pathLabel: 'lib/core/',
  warning: 500,
  blocking: 700,
);

/// 单文件公开类（顶层 class / abstract class / enum / mixin 且不以 `_` 开头）数量上限。
const int kMaxPublicClassesPerFile = 3;

/// 单类公开方法数量上限（静态扫描，仅作为人工 review 指标）。
const int kMaxPublicMethodsPerClass = 25;

/// 存量豁免名单（grandfathered）。
///
/// 这些文件在引入 [FileSizeRule] 之前已严重超线，需要按重构 PR 路线
/// （PR-A / PR-B / PR-C / PR-D / PR-E）逐步拆分。
///
/// **规则**：
/// - 名单内的 blocking 违规会降级为 warning，避免门禁立即全红。
/// - 每完成一个拆分 PR，必须从本名单移除对应条目，**禁止反向追加**。
/// - 仅 blocking 行数 / 公开类数量违规可豁免，`part` / `part of` 违规
///   始终为 blocking。
const Set<String> kFileSizeGrandfathered = <String>{
  'lib/features/audio/services/tts_engine_service.dart',
};

/// 根据相对路径（`/` 风格）找到对应的阈值。返回 `null` 表示该路径不在
/// 任何受控层级（如 `lib/main.dart`），不应用行数门禁。
FileSizeThreshold? resolveFileSizeThreshold(String relativePath) {
  // 路径段精确判断，避免子串误匹配（如 `lib/foo/servicesx/`）。
  final segments = relativePath.split('/');
  if (segments.contains('services')) return kServicesThreshold;
  if (segments.contains('providers')) return kProvidersThreshold;
  if (segments.contains('presentation')) return kPresentationThreshold;
  if (segments.contains('domain')) return kDomainThreshold;
  if (segments.length >= 2 && segments[0] == 'lib' && segments[1] == 'core') {
    return kCoreThreshold;
  }
  return null;
}

/// 计算文件行数，与 IDE 行号 / read_file 工具输出一致。
///
/// 直接使用 `split('\n').length`：
/// - 文件末尾有 LF：最后一个空字符串对应 IDE 中最后一行的空行，行号等于内容行数 + 1。
/// - 文件末尾无 LF：split 不产生空尾元素，等价于内容行数。
///
/// 与 PowerShell `(Get-Content).Count` 的差异：后者会忽略末尾 LF 后的空行，
/// 因此在以 LF 结尾的文件上会比 IDE 行号少 1。门禁以 IDE 行号为准。
int countLines(String content) {
  if (content.isEmpty) return 0;
  return content.split('\n').length;
}
