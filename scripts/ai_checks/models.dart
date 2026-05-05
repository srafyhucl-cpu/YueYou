enum FindingSeverity { blocking, warning }

class AiFinding {
  const AiFinding({
    required this.id,
    required this.severity,
    required this.filePath,
    required this.message,
    this.line,
  });

  final String id;
  final FindingSeverity severity;
  final String filePath;
  final String message;
  final int? line;

  String format() {
    final severityLabel =
        severity == FindingSeverity.blocking ? 'BLOCKING' : 'WARNING';
    final lineSuffix = line == null ? '' : ':$line';
    return '[AI-CHECK][$severityLabel][$id] $filePath$lineSuffix $message';
  }
}

class FileSnapshot {
  FileSnapshot({
    required this.relativePath,
    required this.content,
  }) : lines = content.split('\n');

  final String relativePath;
  final String content;
  final List<String> lines;
}

class AiCheckSummary {
  const AiCheckSummary({
    required this.blockingCount,
    required this.warningCount,
  });

  final int blockingCount;
  final int warningCount;

  bool get hasBlocking => blockingCount > 0;
}
