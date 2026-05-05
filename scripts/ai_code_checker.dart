import 'dart:io';
import 'ai_checks/checker.dart';
export 'ai_checks/checker.dart';
export 'ai_checks/models.dart';

void main() {
  final checker = AiCodeChecker(Directory.current);
  final summary = checker.run();
  stdout.writeln(
    '📊 AI 工程门禁结果：阻断 ${summary.blockingCount} 项，警告 ${summary.warningCount} 项',
  );
  if (summary.hasBlocking) {
    stderr.writeln('❌ AI 工程门禁未通过');
    exitCode = 1;
    return;
  }
  stdout.writeln('✅ AI 工程门禁已通过');
}
