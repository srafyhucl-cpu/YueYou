import 'dart:io';

import 'context.dart';
import 'models.dart';
import 'rules.dart';

class AiCodeChecker {
  AiCodeChecker(this.repoRoot) : _context = AiRepoContext(repoRoot);

  static const List<AiCheckRule> _rules = <AiCheckRule>[
    LegacyAnalyzeFlagRule(),
    TtsLifecycleRule(),
    NotifierGuardsRule(),
    RequiredTestsRule(),
    IllegalConsoleOutputRule(),
    HardcodedUrlRule(),
    ProductionDomainDefaultRule(),
    AndroidBackupRule(),
    DuplicateRegexRule(),
    HardcodedDimensionRule(),
    FileSizeRule(),
  ];

  final Directory repoRoot;
  final AiRepoContext _context;
  final List<AiFinding> _findings = <AiFinding>[];

  List<AiFinding> get findings => List<AiFinding>.unmodifiable(_findings);

  AiCheckSummary run() {
    _findings.clear();
    for (final rule in _rules) {
      rule.apply(_context, _findings);
    }
    _printFindings();

    final blockingCount = _findings
        .where((finding) => finding.severity == FindingSeverity.blocking)
        .length;
    final warningCount = _findings
        .where((finding) => finding.severity == FindingSeverity.warning)
        .length;

    return AiCheckSummary(
      blockingCount: blockingCount,
      warningCount: warningCount,
    );
  }

  void _printFindings() {
    stdout.writeln('🔍 开始 AI 工程门禁检查...');
    if (_findings.isEmpty) {
      stdout.writeln('✅ AI 工程门禁检查通过');
      return;
    }
    for (final finding in _findings) {
      stdout.writeln(finding.format());
    }
  }
}
