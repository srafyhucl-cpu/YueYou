import 'package:flutter_test/flutter_test.dart';

import '../../scripts/check_xiaoyo_ip0.dart';

Map<String, dynamic> _manifest({
  String status = 'candidate',
  bool commercialUseApproved = false,
  bool completeEvidence = false,
}) {
  final evidence = <String, dynamic>{};
  for (final key in [
    'fourViews',
    'expressionTable',
    'materialTable',
    'motionBoundary',
    'similaritySearch',
    'authorizationChain',
  ]) {
    evidence[key] = {
      'complete': completeEvidence,
      'path': completeEvidence ? 'docs/product/assets/$key.md' : null,
    };
  }
  return {
    'schemaVersion': 1,
    'stage': 'IP-0',
    'status': status,
    'commercialUseApproved': commercialUseApproved,
    'requiredEvidence': evidence,
    'assets': [
      {
        'path': 'docs/product/assets/candidate.png',
        'commercialUseAllowed': false,
      },
      {
        'path': 'assets/rive/xiaoyo.riv',
        'commercialUseAllowed': false,
      },
    ],
  };
}

void main() {
  test('未完成 IP-0 证据时保持结构有效但不具备 accepted 状态', () {
    final result = validateXiaoyoIp0Manifest(_manifest());

    expect(result.isValid, isTrue);
    expect(result.isAccepted, isFalse);
    expect(result.warnings, hasLength(6));
  });

  test('商业使用批准不能绕过六类 IP-0 证据', () {
    final result = validateXiaoyoIp0Manifest(
      _manifest(commercialUseApproved: true),
    );

    expect(result.isValid, isFalse);
    expect(result.errors, contains('商业使用批准必须同时满足 accepted 和六类证据完成'));
  });

  test('社区 Rive 资源不能被标记为商业资产', () {
    final manifest = _manifest();
    (manifest['assets'] as List<dynamic>)[1]['commercialUseAllowed'] = true;

    final result = validateXiaoyoIp0Manifest(manifest);

    expect(result.isValid, isFalse);
    expect(result.errors, contains('社区 xiaoyo.riv 不得标记为允许商业使用'));
  });

  test('六类证据完成且 accepted 时才允许商业使用', () {
    final result = validateXiaoyoIp0Manifest(
      _manifest(
        status: 'accepted',
        commercialUseApproved: true,
        completeEvidence: true,
      ),
    );

    expect(result.isValid, isTrue);
    expect(result.isAccepted, isTrue);
  });
}
