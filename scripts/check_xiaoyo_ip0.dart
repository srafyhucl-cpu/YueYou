import 'dart:convert';
import 'dart:io';

const _requiredEvidenceKeys = <String>[
  'fourViews',
  'expressionTable',
  'materialTable',
  'motionBoundary',
  'similaritySearch',
  'authorizationChain',
];

const _acceptedStatuses = <String>{
  'candidate',
  'review',
  'accepted',
  'rejected',
};

final class XiaoyoIp0Validation {
  const XiaoyoIp0Validation({
    required this.errors,
    required this.warnings,
    required this.status,
  });

  final List<String> errors;
  final List<String> warnings;
  final String status;

  bool get isValid => errors.isEmpty;
  bool get isAccepted => status == 'accepted';
}

XiaoyoIp0Validation validateXiaoyoIp0Manifest(
  Map<String, dynamic> manifest,
) {
  final errors = <String>[];
  final warnings = <String>[];
  final status = manifest['status'];

  if (manifest['schemaVersion'] != 1) {
    errors.add('schemaVersion 必须为 1');
  }
  if (manifest['stage'] != 'IP-0') {
    errors.add('stage 必须为 IP-0');
  }
  if (status is! String || !_acceptedStatuses.contains(status)) {
    errors.add('status 必须是 candidate、review、accepted 或 rejected');
  }

  final evidence = manifest['requiredEvidence'];
  final completedEvidence = <String>{};
  if (evidence is! Map<String, dynamic>) {
    errors.add('requiredEvidence 必须是对象');
  } else {
    for (final key in _requiredEvidenceKeys) {
      final item = evidence[key];
      if (item is! Map<String, dynamic>) {
        errors.add('requiredEvidence.$key 必须是对象');
        continue;
      }
      if (item['complete'] == true) {
        completedEvidence.add(key);
      } else {
        warnings.add('IP-0 证据未完成：$key');
      }
      if (item['complete'] == true && item['path'] is! String) {
        errors.add('requiredEvidence.$key 完成后必须提供 path');
      }
    }
  }

  final allEvidenceCompleted =
      completedEvidence.length == _requiredEvidenceKeys.length;
  final commercialUseApproved = manifest['commercialUseApproved'];
  if (commercialUseApproved != false && commercialUseApproved != true) {
    errors.add('commercialUseApproved 必须是布尔值');
  }
  if (commercialUseApproved == true &&
      (status != 'accepted' || !allEvidenceCompleted)) {
    errors.add('商业使用批准必须同时满足 accepted 和六类证据完成');
  }
  if (status == 'accepted' && commercialUseApproved != true) {
    errors.add('status 为 accepted 时必须明确 commercialUseApproved=true');
  }

  final assets = manifest['assets'];
  if (assets is! List<dynamic>) {
    errors.add('assets 必须是数组');
  } else {
    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) {
        errors.add('assets 中的每项必须是对象');
        continue;
      }
      final path = asset['path'];
      if (path is! String || path.isEmpty) {
        errors.add('资产项必须提供非空 path');
        continue;
      }
      if (path == 'assets/rive/xiaoyo.riv' &&
          asset['commercialUseAllowed'] == true) {
        errors.add('社区 xiaoyo.riv 不得标记为允许商业使用');
      }
    }
  }

  if (!allEvidenceCompleted && status == 'accepted') {
    errors.add('六类 IP-0 证据未全部完成，不能进入 accepted');
  }

  return XiaoyoIp0Validation(
    errors: errors,
    warnings: warnings,
    status: status is String ? status : 'invalid',
  );
}

Future<void> main(List<String> args) async {
  final manifestPath = args.firstWhere(
    (arg) => !arg.startsWith('--'),
    orElse: () => 'docs/product/assets/20260714_xiaoyo_v2_ip0_manifest.json',
  );
  final requireAccepted = args.contains('--require-accepted');

  final Map<String, dynamic> manifest;
  try {
    final decoded = jsonDecode(await File(manifestPath).readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('根节点不是 JSON 对象');
    }
    manifest = decoded;
  } on Object catch (error) {
    stderr.writeln('IP-0 清单读取失败：$error');
    exitCode = 1;
    return;
  }

  final result = validateXiaoyoIp0Manifest(manifest);
  for (final warning in result.warnings) {
    stdout.writeln('WARN: $warning');
  }
  if (!result.isValid) {
    for (final error in result.errors) {
      stderr.writeln('ERROR: $error');
    }
    exitCode = 1;
    return;
  }
  if (requireAccepted && !result.isAccepted) {
    stderr.writeln('IP-0 尚未 accepted，禁止继续 Rive/商业资产接入');
    exitCode = 1;
    return;
  }

  stdout.writeln(
    requireAccepted ? 'IP-0 严格门禁通过' : 'IP-0 清单结构通过，当前状态：${result.status}',
  );
}
