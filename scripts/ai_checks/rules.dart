import 'context.dart';
import 'models.dart';
import 'thresholds.dart';

abstract class AiCheckRule {
  const AiCheckRule();

  void apply(AiRepoContext context, List<AiFinding> findings);
}

class LegacyAnalyzeFlagRule extends AiCheckRule {
  const LegacyAnalyzeFlagRule();

  @override
  void apply(AiRepoContext context, List<AiFinding> findings) {
    const files = <String>[
      '.github/workflows/flutter-ci.yml',
      '.windsurf/workflows/code-standardization-check.md',
      '.windsurf/workflows/development-task-closure.md',
    ];
    for (final filePath in files) {
      final snapshot = context.tryReadFile(filePath);
      if (snapshot == null) {
        continue;
      }
      for (var i = 0; i < snapshot.lines.length; i++) {
        if (!snapshot.lines[i].contains('flutter analyze --no-fatal-infos')) {
          continue;
        }
        findings.add(
          AiFinding(
            id: 'analyze.zero_warning_flag',
            severity: FindingSeverity.blocking,
            filePath: filePath,
            line: i + 1,
            message: '发现 `flutter analyze --no-fatal-infos`，与零警告门禁冲突',
          ),
        );
      }
    }
  }
}

class TtsLifecycleRule extends AiCheckRule {
  const TtsLifecycleRule();

  @override
  void apply(AiRepoContext context, List<AiFinding> findings) {
    const filePath = 'lib/features/audio/services/tts_engine_service.dart';
    _requireSnippet(
      context,
      findings,
      filePath: filePath,
      id: 'tts.dispose.progress_controller',
      snippet: '_progressController.close()',
      message: '缺少 StreamController 关闭逻辑',
    );
    _requireSnippet(
      context,
      findings,
      filePath: filePath,
      id: 'tts.dispose.audio_player',
      snippet: '_audioPlayer.dispose()',
      message: '缺少 AudioPlayer 资源释放逻辑',
    );
    _requireSnippet(
      context,
      findings,
      filePath: filePath,
      id: 'tts.dispose.fallback_engine',
      snippet: '_fallbackEngine.stop()',
      message: '缺少本地 TTS 降级引擎停止逻辑',
    );
    _requireSnippet(
      context,
      findings,
      filePath: filePath,
      id: 'tts.dispose.wakelock',
      snippet: '_wakeLock.disable()',
      message: '缺少 Wakelock 释放逻辑',
    );
  }
}

class NotifierGuardsRule extends AiCheckRule {
  const NotifierGuardsRule();

  @override
  void apply(AiRepoContext context, List<AiFinding> findings) {
    const filePath = 'lib/features/audio/providers/tts_audio_notifier.dart';
    _requireSnippet(
      context,
      findings,
      filePath: filePath,
      id: 'tts.pause_interrupt.mark',
      snippet: '_pausedGuard.mark(',
      message: '缺少暂停中断哨兵登记逻辑（PR-D 后委托 _pausedGuard.mark(...)）',
    );
    _requireSnippet(
      context,
      findings,
      filePath: filePath,
      id: 'tts.pause_interrupt.guard',
      snippet: '_pausedGuard.isInterrupt(',
      message: '缺少暂停完成回调拦截逻辑（PR-D 后委托 _pausedGuard.isInterrupt(...)）',
    );
    _requireSnippet(
      context,
      findings,
      filePath: filePath,
      id: 'tts.pause_interrupt.clear',
      snippet: '_pausedGuard.clear(',
      message: '缺少暂停中断哨兵清理逻辑（PR-D 后委托 _pausedGuard.clear()）',
    );
    _requireSnippet(
      context,
      findings,
      filePath: filePath,
      id: 'tts.session_guard.playback',
      snippet: 'if (item.session != _session)',
      message: '缺少播放完成前的旧会话丢弃守卫',
    );
    _requireSnippet(
      context,
      findings,
      filePath: filePath,
      id: 'tts.session_guard.prefetch',
      snippet: 'currentSession != _session',
      message: '缺少预加载完成后的旧会话回写守卫',
    );
  }
}

class RequiredTestsRule extends AiCheckRule {
  const RequiredTestsRule();

  @override
  void apply(AiRepoContext context, List<AiFinding> findings) {
    _requireFile(
      context,
      findings,
      filePath: 'test/features/audio/tts_contract_test.dart',
      id: 'tts.contract_test',
      message: '缺少 TTS 两步下载契约测试',
    );
    _requireFile(
      context,
      findings,
      filePath: 'test/utils/test_utils.dart',
      id: 'test.shared_utils',
      message: '缺少统一测试工具基础设施',
    );
    _requireFile(
      context,
      findings,
      filePath: 'test/features/audio/tts_audio_notifier_test.dart',
      id: 'tts.notifier_regression_test',
      message: '缺少 TTS 状态机回归测试',
    );
  }
}

/// 共享组件只能依赖 Flutter、core 和其他共享组件，禁止反向耦合具体 feature。
class SharedWidgetBoundaryRule extends AiCheckRule {
  const SharedWidgetBoundaryRule();

  @override
  void apply(AiRepoContext context, List<AiFinding> findings) {
    final importPattern = RegExp(
      r'''(?:package:yueyou/features/|package:yueyou/main\.dart|['"](?:\.\./)+features/)''',
    );
    for (final snapshot in context.readDartFilesUnder('lib/shared/widgets')) {
      for (var index = 0; index < snapshot.lines.length; index++) {
        final line = snapshot.lines[index];
        if (!line.trimLeft().startsWith('import ') &&
            !line.trimLeft().startsWith('export ')) {
          continue;
        }
        if (!importPattern.hasMatch(line)) continue;
        findings.add(
          AiFinding(
            id: 'architecture.shared_feature_import',
            severity: FindingSeverity.blocking,
            filePath: snapshot.relativePath,
            line: index + 1,
            message: 'shared/widgets 禁止直接依赖具体 feature 或 main.dart',
          ),
        );
      }
    }
  }
}

class IllegalConsoleOutputRule extends AiCheckRule {
  const IllegalConsoleOutputRule();

  static const Set<String> _consoleOutputAllowlist = <String>{
    'lib/core/utils/cyber_logger.dart',
  };

  @override
  void apply(AiRepoContext context, List<AiFinding> findings) {
    final debugPattern = RegExp(r'debugPrint\s*\(');
    final printPattern = RegExp(r'(^|[^A-Za-z0-9_])print\s*\(');
    for (final snapshot in context.readDartFilesUnder('lib')) {
      if (_consoleOutputAllowlist.contains(snapshot.relativePath)) {
        continue;
      }
      for (var index = 0; index < snapshot.lines.length; index++) {
        final line = snapshot.lines[index];
        final trimmed = line.trimLeft();
        if (context.isCommentLine(trimmed)) {
          continue;
        }
        if (debugPattern.hasMatch(line)) {
          findings.add(
            AiFinding(
              id: 'console.debug_print',
              severity: FindingSeverity.blocking,
              filePath: snapshot.relativePath,
              line: index + 1,
              message: '业务代码中禁止使用 debugPrint()',
            ),
          );
        }
        if (printPattern.hasMatch(line)) {
          findings.add(
            AiFinding(
              id: 'console.print',
              severity: FindingSeverity.blocking,
              filePath: snapshot.relativePath,
              line: index + 1,
              message: '业务代码中禁止直接使用 print()',
            ),
          );
        }
      }
    }
  }
}

class HardcodedUrlRule extends AiCheckRule {
  const HardcodedUrlRule();

  @override
  void apply(AiRepoContext context, List<AiFinding> findings) {
    final urlPattern = RegExp(r'''https?://[^\s'"`]+''');
    for (final snapshot in context.readDartFilesUnder('lib')) {
      for (var index = 0; index < snapshot.lines.length; index++) {
        final line = snapshot.lines[index];
        final trimmed = line.trimLeft();
        if (context.isCommentLine(trimmed)) {
          continue;
        }
        if (!urlPattern.hasMatch(line)) {
          continue;
        }
        if (context.isAllowedUrlContext(snapshot.lines, index)) {
          continue;
        }
        findings.add(
          AiFinding(
            id: 'config.hardcoded_url',
            severity: FindingSeverity.warning,
            filePath: snapshot.relativePath,
            line: index + 1,
            message: '发现疑似硬编码 URL，请确认是否应改为环境变量或配置常量',
          ),
        );
      }
    }
  }
}

/// P0-8 衍生：扫描 `String.fromEnvironment` 的 defaultValue，
/// 如果是非 localhost 的远程 URL（http(s)://...），视为违反"零硬编码"红线 → BLOCKING。
///
/// 允许的本地默认值：localhost / 127.0.0.1 / 10.0.2.2 / 空字符串。
class ProductionDomainDefaultRule extends AiCheckRule {
  const ProductionDomainDefaultRule();

  static final RegExp _fromEnvBlock = RegExp(
    r'''String\.fromEnvironment\s*\(\s*['"]([A-Z0-9_]+)['"]\s*,\s*defaultValue\s*:\s*['"]([^'"]*)['"]''',
    multiLine: true,
  );

  static final List<String> _allowedHosts = <String>[
    'localhost',
    '127.0.0.1',
    '10.0.2.2',
  ];

  /// 允许使用生产域名作为 defaultValue 的 env 白名单。
  /// 这些是公开的"营销/合规"链接（隐私政策、应用市场等），与"零硬编码"红线
  /// 关注的"误连生产 API/TTS 后端"无关，可以安全地随包发布。
  /// 新增条目前必须在 PR 描述中说明合规理由。
  static const Set<String> _allowedMarketingEnvNames = <String>{
    'PRIVACY_POLICY_URL',
    'MARKET_DOWNLOAD_URL',
  };

  @override
  void apply(AiRepoContext context, List<AiFinding> findings) {
    for (final snapshot in context.readDartFilesUnder('lib')) {
      final matches = _fromEnvBlock.allMatches(snapshot.content);
      for (final match in matches) {
        final envName = match.group(1) ?? '';
        final defaultValue = match.group(2) ?? '';
        if (defaultValue.isEmpty) continue;
        if (!defaultValue.startsWith('http://') &&
            !defaultValue.startsWith('https://')) {
          continue;
        }
        if (_allowedMarketingEnvNames.contains(envName)) continue;
        final isAllowedHost = _allowedHosts.any(
          (host) =>
              defaultValue.startsWith('http://$host') ||
              defaultValue.startsWith('https://$host'),
        );
        if (isAllowedHost) continue;
        // 计算所在行号（粗略定位到匹配开头）
        final upToMatch = snapshot.content.substring(0, match.start);
        final line = '\n'.allMatches(upToMatch).length + 1;
        findings.add(
          AiFinding(
            id: 'config.production_default_domain',
            severity: FindingSeverity.blocking,
            filePath: snapshot.relativePath,
            line: line,
            message:
                'String.fromEnvironment("$envName") 的 defaultValue 不得包含非 localhost 的远程域名（当前：$defaultValue）。生产地址必须通过 --dart-define 注入。',
          ),
        );
      }
    }
  }
}

/// Android 本地数据备份边界门禁。
///
/// 阅游的阅读进度、设置、导入书籍与 TTS 缓存均为纯本地数据，未获得用户
/// 明确授权前不得进入系统自动云备份或设备迁移链路。
class AndroidBackupRule extends AiCheckRule {
  const AndroidBackupRule();

  static const String _manifestPath =
      'android/app/src/main/AndroidManifest.xml';

  @override
  void apply(AiRepoContext context, List<AiFinding> findings) {
    final manifest = context.tryReadFile(_manifestPath);
    if (manifest == null) {
      findings.add(
        const AiFinding(
          id: 'android.backup.manifest_missing',
          severity: FindingSeverity.blocking,
          filePath: _manifestPath,
          message: '缺少 AndroidManifest，无法确认本地数据备份边界',
        ),
      );
      return;
    }

    final applicationTag = _applicationTag(manifest.content);
    if (applicationTag == null) {
      findings.add(
        const AiFinding(
          id: 'android.backup.application_missing',
          severity: FindingSeverity.blocking,
          filePath: _manifestPath,
          message: 'AndroidManifest 缺少 <application> 节点',
        ),
      );
      return;
    }

    _requireManifestAttribute(
      findings,
      id: 'android.backup.allow_backup',
      attribute: 'android:allowBackup="false"',
      applicationTag: applicationTag,
      message: '必须显式设置 android:allowBackup="false"，禁止系统自动备份本地数据',
    );
    _requireManifestAttribute(
      findings,
      id: 'android.backup.full_backup_content',
      attribute: 'android:fullBackupContent="false"',
      applicationTag: applicationTag,
      message: '必须显式设置 android:fullBackupContent="false"，阻断旧版完整备份',
    );

    final rulesPath = _dataExtractionRulesPath(applicationTag);
    if (rulesPath == null) {
      findings.add(
        const AiFinding(
          id: 'android.backup.data_extraction_rules',
          severity: FindingSeverity.blocking,
          filePath: _manifestPath,
          message: '必须声明 android:dataExtractionRules，约束 Android 12+ 云备份与设备迁移',
        ),
      );
      return;
    }

    final rules = context.tryReadFile(rulesPath);
    if (rules == null) {
      findings.add(
        AiFinding(
          id: 'android.backup.data_extraction_rules_missing',
          severity: FindingSeverity.blocking,
          filePath: rulesPath,
          message: 'Manifest 引用了 dataExtractionRules，但规则文件不存在',
        ),
      );
      return;
    }
    _checkDataExtractionRules(rules, findings);
  }

  String? _applicationTag(String content) {
    return RegExp(
      r'<application\b[^>]*>',
      multiLine: true,
      dotAll: true,
    ).firstMatch(content)?.group(0);
  }

  void _requireManifestAttribute(
    List<AiFinding> findings, {
    required String id,
    required String attribute,
    required String applicationTag,
    required String message,
  }) {
    if (applicationTag.contains(attribute)) {
      return;
    }
    findings.add(
      AiFinding(
        id: id,
        severity: FindingSeverity.blocking,
        filePath: _manifestPath,
        message: message,
      ),
    );
  }

  String? _dataExtractionRulesPath(String applicationTag) {
    final match = RegExp(
      r'android:dataExtractionRules="@xml/([A-Za-z0-9_]+)"',
    ).firstMatch(applicationTag);
    final resourceName = match?.group(1);
    if (resourceName == null || resourceName.isEmpty) {
      return null;
    }
    return 'android/app/src/main/res/xml/$resourceName.xml';
  }

  void _checkDataExtractionRules(
    FileSnapshot rules,
    List<AiFinding> findings,
  ) {
    final content = rules.content;
    final hasCloudBackup = content.contains('<cloud-backup>') &&
        _hasExclude(content, 'cloud-backup', 'root') &&
        _hasExclude(content, 'cloud-backup', 'file') &&
        _hasExclude(content, 'cloud-backup', 'database') &&
        _hasExclude(content, 'cloud-backup', 'sharedpref');
    final hasDeviceTransfer = content.contains('<device-transfer>') &&
        _hasExclude(content, 'device-transfer', 'root') &&
        _hasExclude(content, 'device-transfer', 'file') &&
        _hasExclude(content, 'device-transfer', 'database') &&
        _hasExclude(content, 'device-transfer', 'sharedpref');

    if (hasCloudBackup && hasDeviceTransfer) {
      return;
    }
    findings.add(
      AiFinding(
        id: 'android.backup.data_extraction_rules_incomplete',
        severity: FindingSeverity.blocking,
        filePath: rules.relativePath,
        message:
            'dataExtractionRules 必须同时排除 cloud-backup 与 device-transfer 的本地文件、数据库和偏好设置',
      ),
    );
  }

  bool _hasExclude(String content, String section, String domain) {
    final sectionMatch = RegExp(
      '<$section>(.*?)</$section>',
      dotAll: true,
    ).firstMatch(content);
    final sectionContent = sectionMatch?.group(1);
    if (sectionContent == null) {
      return false;
    }
    return RegExp(
      '<exclude\\s+domain="$domain"\\s+path="\\."\\s*/>',
    ).hasMatch(sectionContent);
  }
}

void _requireFile(
  AiRepoContext context,
  List<AiFinding> findings, {
  required String filePath,
  required String id,
  required String message,
}) {
  final snapshot = context.tryReadFile(filePath);
  if (snapshot != null) {
    return;
  }
  findings.add(
    AiFinding(
      id: id,
      severity: FindingSeverity.blocking,
      filePath: filePath,
      message: message,
    ),
  );
}

/// 跨文件正则表达式重复检测：若同一 RegExp 字面量出现在 ≥2 个不同文件中 → BLOCKING。
class DuplicateRegexRule extends AiCheckRule {
  const DuplicateRegexRule();

  static final RegExp _regexLiteral = RegExp(r"""RegExp\(\s*r['"](.+?)['"]""");

  @override
  void apply(AiRepoContext context, List<AiFinding> findings) {
    final regexMap = <String, List<String>>{}; // pattern → [filePaths]
    for (final snapshot in context.readDartFilesUnder('lib')) {
      final matches = _regexLiteral.allMatches(snapshot.content);
      for (final match in matches) {
        final pattern = match.group(1) ?? '';
        if (pattern.length < 10) continue; // 跳过过短的正则（如 r'\s'）
        regexMap.putIfAbsent(pattern, () => []).add(snapshot.relativePath);
      }
    }
    for (final entry in regexMap.entries) {
      final files = entry.value.toSet().toList();
      if (files.length < 2) continue;
      findings.add(
        AiFinding(
          id: 'reuse.duplicate_regex',
          severity: FindingSeverity.blocking,
          filePath: files.first,
          message:
              '跨文件正则重复（${files.length} 处）：${files.join(', ')}。请抽取到 core/utils/ 公共工具类。',
        ),
      );
    }
  }
}

void _requireSnippet(
  AiRepoContext context,
  List<AiFinding> findings, {
  required String filePath,
  required String id,
  required String snippet,
  required String message,
}) {
  final snapshot = context.tryReadFile(filePath);
  if (snapshot == null) {
    findings.add(
      AiFinding(
        id: id,
        severity: FindingSeverity.blocking,
        filePath: filePath,
        message: '目标文件不存在，无法执行检查',
      ),
    );
    return;
  }
  if (snapshot.content.contains(snippet)) {
    return;
  }
  findings.add(
    AiFinding(
      id: id,
      severity: FindingSeverity.blocking,
      filePath: filePath,
      message: message,
    ),
  );
}

/// 阅游 presentation / shared 层硬编码 UI 尺寸门禁。
///
/// 检查 `lib/features/*/presentation/`、`lib/shared/` 下的 `.dart` 文件，
/// 发现以下模式时输出 warning：
/// - `blurRadius: <纯数字>`（应使用 CyberDimensions.glowBlurRadius 等）
/// - `sigmaX: <纯数字>` / `sigmaY: <纯数字>`（应使用 CyberDimensions.blur* 常量）
/// - `EdgeInsets.*(` 后跟纯数字参数（应使用 CyberDimensions.spacing* 常量）
/// - `Border.all(` 中 `width: <纯数字>`（应使用 CyberDimensions.border* 常量）
///
/// 豁免：注释行、`// ignore-hardcode` 标记行、`core/theme/` 定义文件本身。
class HardcodedDimensionRule extends AiCheckRule {
  const HardcodedDimensionRule();

  /// 匹配 `blurRadius: <数字>` 且后面不跟 `CyberDimensions`
  static final RegExp _blurRadiusPattern = RegExp(
    r'blurRadius:\s+(\d+\.?\d*)',
  );

  /// 匹配 `sigmaX: <数字>` 或 `sigmaY: <数字>` 且不是 CyberDimensions
  static final RegExp _sigmaPattern = RegExp(
    r'sigma[XY]:\s+(\d+\.?\d*)',
  );

  /// 匹配 `EdgeInsets.all(<数字>)` / `EdgeInsets.symmetric(horizontal: <数字>` 等
  static final RegExp _edgeInsetsNumericPattern = RegExp(
    r'EdgeInsets\.\w+\(\s*(?:horizontal:\s*|vertical:\s*)?(\d+\.?\d*)',
  );

  /// 跳过的值（0, 0.0, 1, 1.0 等标识性数值）
  static bool _isTrivialValue(String value) {
    final v = double.tryParse(value);
    return v != null && (v == 0 || v == 1 || v == -1);
  }

  /// 受检路径：presentation 层和 shared 层
  static bool _isTargetPath(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    return normalized.contains('/presentation/') ||
        normalized.startsWith('lib/shared/');
  }

  /// 排除的定义文件（常量定义本身不算硬编码）
  static bool _isThemeDefinition(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    return normalized.contains('core/theme/');
  }

  @override
  void apply(AiRepoContext context, List<AiFinding> findings) {
    for (final snapshot in context.readDartFilesUnder('lib')) {
      if (!_isTargetPath(snapshot.relativePath)) continue;
      if (_isThemeDefinition(snapshot.relativePath)) continue;

      for (var i = 0; i < snapshot.lines.length; i++) {
        final line = snapshot.lines[i];
        final trimmed = line.trimLeft();
        if (context.isCommentLine(trimmed)) continue;
        if (line.contains('// ignore-hardcode')) continue;
        // 跳过已使用 CyberDimensions 的行
        if (line.contains('CyberDimensions')) continue;

        _checkPattern(
          _blurRadiusPattern,
          line,
          i,
          snapshot,
          findings,
          'blurRadius',
        );
        _checkPattern(
          _sigmaPattern,
          line,
          i,
          snapshot,
          findings,
          'sigma',
        );
        _checkEdgeInsets(line, i, snapshot, findings);
      }
    }
  }

  void _checkPattern(
    RegExp pattern,
    String line,
    int lineIndex,
    FileSnapshot snapshot,
    List<AiFinding> findings,
    String propertyName,
  ) {
    final match = pattern.firstMatch(line);
    if (match == null) return;
    final value = match.group(1) ?? '';
    if (_isTrivialValue(value)) return;
    findings.add(
      AiFinding(
        id: 'hardcode.dimension.$propertyName',
        severity: FindingSeverity.warning,
        filePath: snapshot.relativePath,
        line: lineIndex + 1,
        message: '$propertyName: $value 应使用 CyberDimensions 常量，'
            '或添加 `// ignore-hardcode` 标记豁免',
      ),
    );
  }

  void _checkEdgeInsets(
    String line,
    int lineIndex,
    FileSnapshot snapshot,
    List<AiFinding> findings,
  ) {
    final match = _edgeInsetsNumericPattern.firstMatch(line);
    if (match == null) return;
    final value = match.group(1) ?? '';
    if (_isTrivialValue(value)) return;
    findings.add(
      AiFinding(
        id: 'hardcode.dimension.edge_insets',
        severity: FindingSeverity.warning,
        filePath: snapshot.relativePath,
        line: lineIndex + 1,
        message: 'EdgeInsets 参数 $value 应使用 CyberDimensions.spacing* 常量，'
            '或添加 `// ignore-hardcode` 标记豁免',
      ),
    );
  }
}

/// 阅游单文件体量与上帝类反模式门禁。
///
/// 红线来源：`.windsurf/rules/AGENT.md` 第 8 条 / `CLAUDE.md` 同名章节。
/// 联动技能：`.agents/skills/yueyou-file-size-guard/SKILL.md`。
/// 联动工作流：`.windsurf/workflows/large-file-refactor-review.md`。
///
/// 检查范围（仅 `lib/` 下的 `.dart` 文件）：
/// 1. **行数**：超过 [FileSizeThreshold.warning] 输出 warning；超过
///    [FileSizeThreshold.blocking] 输出 blocking。
/// 2. **公开类数量**：超过 [kMaxPublicClassesPerFile] 输出 blocking。
/// 3. **`part` / `part of` 禁用**：发现即 blocking，禁止用 part 拆分规避行数门禁。
///
/// 存量豁免：[kFileSizeGrandfathered] 列表中的文件，1 / 2 类违规会降级为
/// warning；3 类（part 指令）始终为 blocking。
class FileSizeRule extends AiCheckRule {
  const FileSizeRule();

  static final RegExp _topLevelClassPattern = RegExp(
    r'^(?:abstract\s+)?(?:class|enum|mixin)\s+([A-Za-z_][A-Za-z0-9_]*)',
    multiLine: true,
  );

  static final RegExp _partDirectivePattern = RegExp(
    r'''^\s*part(\s+of)?\s+['"]''',
  );

  @override
  void apply(AiRepoContext context, List<AiFinding> findings) {
    for (final snapshot in context.readDartFilesUnder('lib')) {
      _checkLineCount(snapshot, findings);
      _checkPublicClassCount(snapshot, findings);
      _checkPartDirective(snapshot, findings);
    }
  }

  void _checkLineCount(FileSnapshot snapshot, List<AiFinding> findings) {
    final threshold = resolveFileSizeThreshold(snapshot.relativePath);
    if (threshold == null) return;
    final lines = countLines(snapshot.content);
    final isGrandfathered =
        kFileSizeGrandfathered.contains(snapshot.relativePath);
    if (lines >= threshold.blocking) {
      findings.add(
        AiFinding(
          id: 'file_size.exceeds_blocking',
          severity: isGrandfathered
              ? FindingSeverity.warning
              : FindingSeverity.blocking,
          filePath: snapshot.relativePath,
          message: isGrandfathered
              ? '文件行数 $lines 超过硬上限 ${threshold.blocking}'
                  '（${threshold.pathLabel}）；存量豁免，必须按重构 PR 路线拆分后从 '
                  'kFileSizeGrandfathered 移除'
              : '文件行数 $lines 超过硬上限 ${threshold.blocking}'
                  '（${threshold.pathLabel}）；必须先走 '
                  'large-file-refactor-review 工作流拆分',
        ),
      );
    } else if (lines >= threshold.warning) {
      findings.add(
        AiFinding(
          id: 'file_size.exceeds_warning',
          severity: FindingSeverity.warning,
          filePath: snapshot.relativePath,
          message: '文件行数 $lines 超过警戒线 ${threshold.warning}'
              '（${threshold.pathLabel}）；不得继续在该文件追加新职责',
        ),
      );
    }
  }

  void _checkPublicClassCount(
    FileSnapshot snapshot,
    List<AiFinding> findings,
  ) {
    var publicCount = 0;
    for (final match in _topLevelClassPattern.allMatches(snapshot.content)) {
      final name = match.group(1) ?? '';
      if (name.isEmpty || name.startsWith('_')) continue;
      publicCount++;
    }
    if (publicCount <= kMaxPublicClassesPerFile) return;
    final isGrandfathered =
        kFileSizeGrandfathered.contains(snapshot.relativePath);
    findings.add(
      AiFinding(
        id: 'file_size.too_many_public_classes',
        severity: isGrandfathered
            ? FindingSeverity.warning
            : FindingSeverity.blocking,
        filePath: snapshot.relativePath,
        message: isGrandfathered
            ? '单文件公开类数量 $publicCount 超过上限 '
                '$kMaxPublicClassesPerFile；存量豁免，必须按四象限拆分'
            : '单文件公开类数量 $publicCount 超过上限 '
                '$kMaxPublicClassesPerFile；请按四象限拆分到独立文件',
      ),
    );
  }

  void _checkPartDirective(FileSnapshot snapshot, List<AiFinding> findings) {
    for (var i = 0; i < snapshot.lines.length; i++) {
      final line = snapshot.lines[i];
      if (!_partDirectivePattern.hasMatch(line)) continue;
      findings.add(
        AiFinding(
          id: 'file_size.part_directive',
          severity: FindingSeverity.blocking,
          filePath: snapshot.relativePath,
          line: i + 1,
          message: '禁止使用 part / part of 规避单文件行数门禁，请拆为独立文件',
        ),
      );
    }
  }
}
