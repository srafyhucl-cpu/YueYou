import 'dart:convert';
import 'dart:io';

import 'commerce_experiment_evaluator.dart';

/// 读取匿名聚合 JSON 并输出商业停止线计算结果。
Future<void> main(List<String> args) async {
  final inputPath = args.firstWhere(
    (arg) => !arg.startsWith('--'),
    orElse: () => '',
  );
  if (inputPath.isEmpty) {
    stderr.writeln(
      '用法：dart run scripts/evaluate_commerce_experiment.dart <聚合 JSON 路径>',
    );
    exitCode = 64;
    return;
  }

  try {
    final decoded = jsonDecode(await File(inputPath).readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('输入根节点必须是 JSON 对象');
    }
    final schemaVersion = decoded['schemaVersion'];
    if (schemaVersion != 1) {
      throw const FormatException('schemaVersion 必须为 1');
    }
    final aggregate = CommerceExperimentAggregate.fromJson(decoded);
    final report = evaluateCommerceExperiment(aggregate);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
  } on Object catch (error) {
    stderr.writeln('商业实验聚合数据无效：$error');
    exitCode = 1;
  }
}
