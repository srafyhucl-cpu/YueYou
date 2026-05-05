import 'dart:io';

import 'models.dart';

class AiRepoContext {
  const AiRepoContext(this.repoRoot);

  final Directory repoRoot;

  Iterable<FileSnapshot> readDartFilesUnder(String directoryPath) sync* {
    final dir = Directory(absolutePath(directoryPath));
    if (!dir.existsSync()) {
      return;
    }
    List<FileSystemEntity> entities;
    try {
      entities = dir.listSync(recursive: true);
    } on FileSystemException {
      return;
    }
    for (final entity in entities) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final relative = relativePath(entity.path);
      final String content;
      try {
        content = entity.readAsStringSync();
      } on FileSystemException {
        continue;
      }
      yield FileSnapshot(
        relativePath: relative,
        content: content,
      );
    }
  }

  FileSnapshot? tryReadFile(String relativePath) {
    final file = File(absolutePath(relativePath));
    if (!file.existsSync()) {
      return null;
    }
    final String content;
    try {
      content = file.readAsStringSync();
    } on FileSystemException {
      return null;
    }
    return FileSnapshot(
      relativePath: relativePath,
      content: content,
    );
  }

  bool isAllowedUrlContext(List<String> lines, int index) {
    final start = index - 4 < 0 ? 0 : index - 4;
    final end = index + 1 >= lines.length ? lines.length - 1 : index + 1;
    final window = lines.sublist(start, end + 1).join('\n');
    return window.contains('String.fromEnvironment(');
  }

  bool isCommentLine(String trimmedLine) {
    return trimmedLine.startsWith('//') ||
        trimmedLine.startsWith('/*') ||
        trimmedLine.startsWith('*') ||
        trimmedLine.startsWith('///');
  }

  String absolutePath(String relativePath) {
    final normalized = relativePath.replaceAll('/', Platform.pathSeparator);
    return '${repoRoot.path}${Platform.pathSeparator}$normalized';
  }

  String relativePath(String absolutePath) {
    final normalizedAbsolute = absolutePath.replaceAll('\\', '/');
    final normalizedRoot = repoRoot.absolute.path.replaceAll('\\', '/');
    if (!normalizedAbsolute.startsWith(normalizedRoot)) {
      return normalizedAbsolute;
    }
    final relative = normalizedAbsolute.substring(normalizedRoot.length + 1);
    return relative;
  }
}
